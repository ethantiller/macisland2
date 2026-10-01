import AudioToolbox
import CoreAudio
import Foundation

/// A running tap: one app's sound, taken out of the system mix and played again, at a level, on an output.
protocol AudioTap: AnyObject {
    /// Whether any sound has come through. A tap that is allowed hears the app; one that isn't hears silence.
    var heardSound: Bool { get }
    func setLevel(_ level: Float)
    /// Stops the sound and gives everything back, so the app is heard directly again.
    func stop()
}

/// Makes taps. Behind a protocol so the Mixer's rules are tested without Core Audio.
@MainActor
protocol AudioTapping: AnyObject {
    /// Taps these processes and plays them on the output with this UID (the default output if nil). Nil if it could not be done.
    func start(processObjects: [AudioObjectID], outputUID: String?, level: Float) -> AudioTap?
    /// Taps MacIsland's own process for a moment: what makes macOS ask for System Audio Recording.
    func probe() async
}

/// The audio thread's side of a tap. Everything it touches is made before the tap starts: it allocates nothing while running.
final class TapState: @unchecked Sendable {
    /// Written on the main thread, read on the audio thread: a 32-bit store, which is atomic on every Mac.
    var level: Float
    private(set) var heard = false
    private var limiter: BoostLimiter?
    private var scratch: [Float]
    private var sampleRate: Double

    init(level: Float, sampleRate: Double) {
        self.level = level
        self.sampleRate = sampleRate
        scratch = [Float](repeating: 0, count: 4096)
        limiter = BoostLimiter(channels: 2, sampleRate: sampleRate)
    }

    /// Before the tap starts: the output's real rate, so the limiter's look-ahead and release are right.
    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate
        limiter = BoostLimiter(channels: 2, sampleRate: sampleRate)
    }

    /// Copies the tap's input to the output times the level, buffer by buffer.
    func process(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let level = self.level
        for index in 0..<outputs.count {
            guard index < inputs.count, let from = inputs[index].mData, let to = outputs[index].mData else {
                if let to = outputs[index].mData { memset(to, 0, Int(outputs[index].mDataByteSize)) }
                continue
            }
            let inChannels = max(Int(inputs[index].mNumberChannels), 1)
            let outChannels = max(Int(outputs[index].mNumberChannels), 1)
            let frames = min(
                Int(inputs[index].mDataByteSize) / (MemoryLayout<Float>.size * inChannels),
                Int(outputs[index].mDataByteSize) / (MemoryLayout<Float>.size * outChannels))
            let source = from.assumingMemoryBound(to: Float.self)
            let target = to.assumingMemoryBound(to: Float.self)
            if limiter?.channels != inChannels { limiter = BoostLimiter(channels: inChannels, sampleRate: sampleRate) }
            if !heard { heard = Self.hasSound(source, count: frames * inChannels) }
            if inChannels == outChannels {
                limiter?.process(source, into: target, frames: frames, level: level)
            } else {
                // A different layout (a mono output): the first channels through, the rest silent.
                if scratch.count < frames * inChannels { scratch = [Float](repeating: 0, count: frames * inChannels) }
                scratch.withUnsafeMutableBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    limiter?.process(source, into: base, frames: frames, level: level)
                    for frame in 0..<frames {
                        for channel in 0..<outChannels {
                            target[frame * outChannels + channel] = channel < inChannels ? base[frame * inChannels + channel] : 0
                        }
                    }
                }
            }
        }
    }

    private static func hasSound(_ samples: UnsafePointer<Float>, count: Int) -> Bool {
        for index in 0..<count where abs(samples[index]) > 0.00001 { return true }
        return false
    }
}

/// The live tap: a Core Audio process tap, a private aggregate device with the tap and the chosen output in it, and an IO proc that
/// moves the sound across. Nothing here is a driver, and everything is private to this process: if MacIsland quits or crashes, Core
/// Audio removes the tap and the app is heard directly again (**verify** on the owner's Mac).
@MainActor
final class CoreAudioTapper: AudioTapping {
    func start(processObjects: [AudioObjectID], outputUID: String?, level: Float) -> AudioTap? {
        guard !processObjects.isEmpty else { return nil }
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects.map { NSNumber(value: $0) })
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        return CoreAudioTap(description: description, outputUID: outputUID ?? Self.defaultOutputUID(), level: level)
    }

    func probe() async {
        // The first tap is what macOS asks about. MacIsland's own process is the only one that can be tapped without disturbing anyone.
        let me = AudioObjectID(Self.processObject(forPID: ProcessInfo.processInfo.processIdentifier))
        guard me != AudioObjectID(kAudioObjectUnknown) else { return }
        guard let tap = start(processObjects: [me], outputUID: nil, level: 1) else { return }
        try? await Task.sleep(for: .milliseconds(400))
        tap.stop()
    }

    // MARK: Devices

    static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }
        return deviceUID(device)
    }

    static func deviceUID(_ device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func processObject(forPID pid: Int32) -> AudioObjectID {
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<Int32>.size), &pid, &size, &object)
        return object
    }
}

@MainActor
final class CoreAudioTap: AudioTap {
    private let state: TapState
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.ethantiller.MacIsland.mixer", qos: .userInteractive)

    var heardSound: Bool { state.heard }

    /// Nil from the factory below if any step fails, with what was made already given back.
    init?(description: CATapDescription, outputUID: String?, level: Float) {
        state = TapState(level: level, sampleRate: 48_000)
        guard let outputUID else { return nil }
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return nil }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacIsland Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
            ],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            release()
            return nil
        }
        var rate = Float64(48_000)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(aggregateID, &rateAddress, 0, nil, &rateSize, &rate) == noErr, rate > 0 {
            state.configure(sampleRate: rate)
        }
        let state = state
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
            state.process(input, output)
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else {
            release()
            return nil
        }
    }

    func setLevel(_ level: Float) {
        state.level = level
    }

    func stop() {
        release()
    }

    private func release() {
        if let procID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}
