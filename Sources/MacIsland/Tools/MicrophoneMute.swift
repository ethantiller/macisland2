import CoreAudio
import Foundation
import Observation

/// Mutes the default input device. Uses the device's mute switch when it has one, otherwise
/// sets its input volume to zero and restores it on unmute.
@MainActor
@Observable
final class MicrophoneMute {
    /// Read from the device; tests set it to stand in for one.
    var isMuted = false
    private(set) var isAvailable = false

    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var volumeBeforeMute: Float32 = 0.75

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    init() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.listener = listener
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(Self.system, &address, .main, listener)
        refresh()
    }

    func refresh() {
        guard let device = Self.defaultInput() else {
            isAvailable = false
            return
        }
        if Self.isSettable(device, kAudioDevicePropertyMute),
            let mute: UInt32 = Self.read(device, kAudioDevicePropertyMute)
        {
            isAvailable = true
            isMuted = mute == 1
        } else if Self.isSettable(device, kAudioDevicePropertyVolumeScalar),
            let volume: Float32 = Self.read(device, kAudioDevicePropertyVolumeScalar)
        {
            isAvailable = true
            isMuted = volume == 0
        } else {
            isAvailable = false
        }
    }

    func toggle() {
        guard let device = Self.defaultInput() else { return }
        if Self.isSettable(device, kAudioDevicePropertyMute) {
            Self.write(device, kAudioDevicePropertyMute, UInt32(isMuted ? 0 : 1))
        } else if Self.isSettable(device, kAudioDevicePropertyVolumeScalar) {
            if isMuted {
                Self.write(device, kAudioDevicePropertyVolumeScalar, volumeBeforeMute)
            } else {
                if let current: Float32 = Self.read(device, kAudioDevicePropertyVolumeScalar), current > 0 {
                    volumeBeforeMute = current
                }
                Self.write(device, kAudioDevicePropertyVolumeScalar, Float32(0))
            }
        }
        refresh()
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeInput
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultInput() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func isSettable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func read<T: Numeric & BitwiseCopyable>(
        _ device: AudioDeviceID, _ selector: AudioObjectPropertySelector
    ) -> T? {
        var address = address(selector)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func write<T: BitwiseCopyable>(
        _ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: T
    ) {
        var address = address(selector)
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }
}
