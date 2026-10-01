import AppKit
import CoreAudio
import Darwin

/// An app that makes sound, as the Mixer sees it: a Core Audio process or several (a browser's helpers), grouped under the app.
struct MixerApp: Identifiable, Equatable {
    /// The app's bundle ID.
    var id: String
    var name: String
    /// The Core Audio process objects to tap: the app's and its helpers'.
    var processObjects: [AudioObjectID]
    /// Whether any of them is running output now.
    var isPlaying: Bool

    /// Calls and pro-audio apps stay as they are: latency matters more than volume there.
    var isNeverTapped: Bool { AppMixer.neverTapped(bundleID: id) }
}

/// Who owns a helper process. Pure, so it is tested without processes.
enum AppGrouping {
    /// The nearest process at or above `pid` that `isApp` accepts, walking up through parents (at most 12 steps, and never in a
    /// loop). Nil if there is none.
    static func owner(of pid: Int32, parent: (Int32) -> Int32?, isApp: (Int32) -> Bool) -> Int32? {
        var current = pid
        var seen: Set<Int32> = []
        for _ in 0..<12 {
            if isApp(current) { return current }
            guard seen.insert(current).inserted, let next = parent(current), next > 1, next != current else { return nil }
            current = next
        }
        return nil
    }
}

/// Where the Mixer learns which apps make sound. Behind a protocol so tests push a list by hand.
@MainActor
protocol AppAudioListing: AnyObject {
    /// Called when the list of processes, or whether one is running output, changes.
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
    func current() -> [MixerApp]
}

/// The apps from Core Audio's process list. It listens (no polling): to the list, and to whether each process is running output, the way
/// `PrivacyMonitor` follows the microphone.
@MainActor
final class CoreAudioAppList: AppAudioListing {
    var onChange: (() -> Void)?

    private var listener: AudioObjectPropertyListenerBlock?
    private var watched: Set<AudioObjectID> = []
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    func start() {
        guard listener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        self.listener = listener
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(Self.system, &address, .main, listener)
        watchNewProcesses()
    }

    func stop() {
        guard let listener else { return }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(Self.system, &address, .main, listener)
        for process in watched {
            var running = Self.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(process, &running, .main, listener)
        }
        watched = []
        self.listener = nil
    }

    private func changed() {
        watchNewProcesses()
        onChange?()
    }

    private func watchNewProcesses() {
        guard let listener else { return }
        let processes = Self.processObjects()
        watched.formIntersection(processes)
        for process in processes where watched.insert(process).inserted {
            var address = Self.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectAddPropertyListenerBlock(process, &address, .main, listener)
        }
    }

    func current() -> [MixerApp] {
        struct Entry {
            var object: AudioObjectID
            var pid: Int32
            var bundleID: String?
            var isPlaying: Bool
        }
        let entries = Self.processObjects().compactMap { object -> Entry? in
            guard let pid = Self.int32(object, kAudioProcessPropertyPID) else { return nil }
            return Entry(
                object: object, pid: pid, bundleID: Self.string(object, kAudioProcessPropertyBundleID),
                isPlaying: Self.uint32(object, kAudioProcessPropertyIsRunningOutput) == 1)
        }
        var grouped: [String: MixerApp] = [:]
        var order: [String] = []
        for entry in entries {
            let owner = AppGrouping.owner(
                of: entry.pid, parent: { Self.parentPID(of: $0) }, isApp: { Self.isUserApp(pid: $0) })
            let application = owner.flatMap { NSRunningApplication(processIdentifier: $0) }
            guard let id = application?.bundleIdentifier ?? entry.bundleID, !id.isEmpty else { continue }
            let name = application?.localizedName ?? id
            if var app = grouped[id] {
                app.processObjects.append(entry.object)
                app.isPlaying = app.isPlaying || entry.isPlaying
                grouped[id] = app
            } else {
                grouped[id] = MixerApp(id: id, name: name, processObjects: [entry.object], isPlaying: entry.isPlaying)
                order.append(id)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
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

    private static func int32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var address = address(selector)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// The parent of a process, from the kernel's process info (public `libproc`; no private calls).
    private static func parentPID(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbi_ppid)
    }

    /// An app a person would name: it has a bundle and shows in the Dock or the menu bar.
    private static func isUserApp(pid: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: pid), application.bundleURL != nil else { return false }
        return application.activationPolicy != .prohibited
    }
}
