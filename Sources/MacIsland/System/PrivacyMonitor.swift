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

    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?
    /// The devices and processes that have the listener, so each new one gets it once.
    @ObservationIgnored private var watched: Set<AudioObjectID> = []

    /// Listens rather than polls (a poll was a standing timer while nothing is live): to the device and process lists,
    /// to whether each device is running somewhere, and to whether each process is taking input.
    func start() {
        guard listener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.listener = listener
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyProcessObjectList] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(Self.system, &address, .main, listener)
        }
        refresh()
    }

    private func refresh() {
        watchNewObjects()
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

    /// Devices and processes come and go. An id that is gone is forgotten, so if CoreAudio reuses it, the new object is
    /// watched.
    private func watchNewObjects() {
        guard let listener else { return }
        let devices = Self.objectList(kAudioHardwarePropertyDevices)
        let processes = Self.objectList(kAudioHardwarePropertyProcessObjectList)
        watched.formIntersection(devices + processes)
        for (objects, selector) in [
            (devices, kAudioDevicePropertyDeviceIsRunningSomewhere),
            (processes, kAudioProcessPropertyIsRunningInput),
        ] {
            for object in objects where watched.insert(object).inserted {
                var address = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(object, &address, .main, listener)
            }
        }
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
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size > 0 else {
                return false
            }
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
