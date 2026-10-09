import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

/// A running tap: one app's sound, taken out of the system mix and played again, at a level, on an output.
@MainActor
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
    /// The most output streams that are limited; any more play silence.
    private static let maxStreams = 4
    private static let scratchSamples = 16_384

    /// Written on the main thread, read on the audio thread, so both go through atomics.
    private let levelBits: Atomic<UInt32>
    private let heardFlag = Atomic<Bool>(false)
    /// One limiter for each output stream, because each remembers the last few milliseconds of its own sound.
    private var limiters: [BoostLimiter]
    private var scratch: [Float]
    private var sampleRate: Double

    var level: Float {
        get { Float(bitPattern: levelBits.load(ordering: .relaxed)) }
        set { levelBits.store(newValue.bitPattern, ordering: .relaxed) }
    }
    var heard: Bool { heardFlag.load(ordering: .relaxed) }

    init(level: Float, sampleRate: Double) {
        levelBits = Atomic(level.bitPattern)
        self.sampleRate = sampleRate
        scratch = [Float](repeating: 0, count: Self.scratchSamples)
        limiters = Self.makeLimiters(sampleRate: sampleRate)
    }

    private static func makeLimiters(sampleRate: Double) -> [BoostLimiter] {
        (0..<maxStreams).map { _ in BoostLimiter(channels: 2, sampleRate: sampleRate) }
    }

    /// Before the tap starts: the output's real rate, so the limiter's look-ahead and release are right.
    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate
        limiters = Self.makeLimiters(sampleRate: sampleRate)
    }

    /// Copies the tap's sound to every output stream times the level. The tap is the last input stream: an output device with a
    /// microphone (a headset) puts its own input streams before it, and those must never be played back.
    func process(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let requested = level
        let level = requested.isFinite ? requested : 1
        for index in 0..<outputs.count {
            guard let to = outputs[index].mData else { continue }
            let byteCount = Int(outputs[index].mDataByteSize)
            guard inputs.count > 0, index < Self.maxStreams, let from = inputs[inputs.count - 1].mData else {
                memset(to, 0, byteCount)
                continue
            }
            let tap = inputs[inputs.count - 1]
            let inChannels = max(Int(tap.mNumberChannels), 1)
            let outChannels = max(Int(outputs[index].mNumberChannels), 1)
            let frames = min(
                Int(tap.mDataByteSize) / (MemoryLayout<Float>.size * inChannels),
                byteCount / (MemoryLayout<Float>.size * outChannels))
            let source = from.assumingMemoryBound(to: Float.self)
            let target = to.assumingMemoryBound(to: Float.self)
            if limiters[index].channels != inChannels {
                // Not the stereo mixdown that was expected: the one case that allocates.
                limiters[index] = BoostLimiter(channels: inChannels, sampleRate: sampleRate)
            }
            if !heard && Self.hasSound(source, count: frames * inChannels) { heardFlag.store(true, ordering: .relaxed) }
            if inChannels == outChannels {
                limiters[index].process(source, into: target, frames: frames, level: level)
            } else {
                // A different layout (a mono output): the first channels through, the rest silent.
                let chunk = max(Self.scratchSamples / inChannels, 1)
                scratch.withUnsafeMutableBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    var done = 0
                    while done < frames {
                        let count = min(chunk, frames - done)
                        limiters[index].process(source + done * inChannels, into: base, frames: count, level: level)
                        for frame in 0..<count {
                            for channel in 0..<outChannels {
                                target[(done + frame) * outChannels + channel] =
                                    channel < inChannels ? base[frame * inChannels + channel] : 0
                            }
                        }
                        done += count
                    }
                }
            }
            // A sample that is not a number would be heard as a pop: silence instead.
            for sample in 0..<frames * outChannels where !target[sample].isFinite { target[sample] = 0 }
            if frames * outChannels * MemoryLayout<Float>.size < byteCount {
                memset(
                    to + frames * outChannels * MemoryLayout<Float>.size, 0, byteCount - frames * outChannels * MemoryLayout<Float>.size)
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
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
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
