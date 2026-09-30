import AppKit
import CoreAudio
import SwiftUI

/// Whether any app is using the microphone, and which one. macOS already draws its own
/// indicator dots, so the island only adds the app and duration.
@MainActor
@Observable
final class PrivacyMonitor {
    private(set) var isMicrophoneInUse = false
    private(set) var microphoneSince: Date?
    private(set) var microphoneAppBundleID: String?

    @ObservationIgnored private var timer: Timer?

    func start() {
        refresh()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        let microphone = Self.microphoneInUse()
        if microphone != isMicrophoneInUse {
            withAnimation(Theme.Motion.open) {
                isMicrophoneInUse = microphone
                microphoneSince = microphone ? Date() : nil
            }
        }
        let app = microphone ? Self.microphoneApp() : nil
        if app != microphoneAppBundleID { microphoneAppBundleID = app }
    }

    // MARK: Microphone (CoreAudio)

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func microphoneInUse() -> Bool {
        objectList(kAudioHardwarePropertyDevices).contains { device in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size > 0 else { return false }
            return uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
        }
    }

    private static func microphoneApp() -> String? {
        for process in objectList(kAudioHardwarePropertyProcessObjectList)
        where uint32(process, kAudioProcessPropertyIsRunningInput) == 1 {
            var address = address(kAudioProcessPropertyBundleID)
            var name: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &name) == noErr,
                  let bundleID = name?.takeRetainedValue() as String?,
                  !bundleID.isEmpty, bundleID != Bundle.main.bundleIdentifier
            else { continue }
            return bundleID
        }
        return nil
    }
}
