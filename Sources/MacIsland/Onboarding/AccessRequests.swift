import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import EventKit
import Foundation
import Intents
import Observation
import Speech

/// The permissions the first-run guide walks through, one at a time, in the order it asks. The raw value is `PrivacyAccess.id`.
enum AccessKind: String, CaseIterable {
    case calendars, reminders, bluetooth, downloads, camera, microphone
    case screenRecording = "screen"
    case accessibility, focus, automation
}

extension AccessKind {
    var symbol: String {
        switch self {
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .bluetooth: "headphones"
        case .downloads: "arrow.down.circle"
        case .camera: "camera"
        case .microphone: "mic"
        case .screenRecording: "record.circle"
        case .accessibility: "keyboard"
        case .focus: "moon"
        case .automation: "music.note"
        }
    }

    var title: String {
        switch self {
        case .calendars: "Calendars"
        case .reminders: "Reminders"
        case .bluetooth: "Bluetooth"
        case .downloads: "Downloads"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        case .focus: "Focus"
        case .automation: "Automation"
        }
    }

    /// Why MacIsland asks, in terms of what the person gets. One short line, for lists.
    var reason: String {
        switch self {
        case .calendars: "Your next meeting in Up Next, and a banner before it starts"
        case .reminders: "Your reminders in their tab, and a banner when one is due"
        case .bluetooth: "Your headphones and their battery when they connect"
        case .downloads: "Progress while a file downloads, and a nudge when it lands"
        case .camera: "The Mirror"
        case .microphone: "Voice notes, turned into text on this Mac"
        case .screenRecording: "Record Screen"
        case .accessibility: "Clean Keys"
        case .focus: "Holding banners back while a Focus is on"
        case .automation: "Play, pause, and Favorite in Music and Spotify"
        }
    }

    /// The System Settings pane where a denied permission is turned back on.
    var settingsURL: URL? {
        let pane: String =
            switch self {
            case .calendars: "Privacy_Calendars"
            case .reminders: "Privacy_Reminders"
            case .bluetooth: "Privacy_Bluetooth"
            case .downloads: "Privacy_FilesAndFolders"
            case .camera: "Privacy_Camera"
            case .microphone: "Privacy_Microphone"
            case .screenRecording: "Privacy_ScreenCapture"
            case .accessibility: "Privacy_Accessibility"
            case .focus: "Privacy_Focus"
            case .automation: "Privacy_Automation"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}

/// Which permissions MacIsland has asked for, for the ones the system can't tell "never asked" from "off": Downloads can't be read
/// without asking, and Screen Recording and Accessibility only say whether they are on. Kept in `UserDefaults`; the guide's
/// `make first-run` clears it.
enum AccessAsked {
    static let key = "access.asked"

    static func contains(_ kind: AccessKind, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(kind.rawValue)
    }

    static func mark(_ kind: AccessKind, defaults: UserDefaults = .standard) {
        var asked = defaults.stringArray(forKey: key) ?? []
        guard !asked.contains(kind.rawValue) else { return }
        asked.append(kind.rawValue)
        defaults.set(asked, forKey: key)
    }
}

@MainActor
protocol AccessProviding: AnyObject {
    func state(of kind: AccessKind) -> PrivacyAccess.State
    /// Asks the system if it was never asked, and says whether access is now allowed. For a permission the system won't
    /// answer for, it says whether the request was made.
    func request(_ kind: AccessKind) async -> Bool
    /// Reads what can only be read off the main actor (Automation), so the next `state(of:)` is true. Nothing for most providers.
    func reload() async
    /// For a step that needs more than one permission (Microphone needs Speech Recognition too): the one that is off, if it isn't the
    /// step's own name. Nil otherwise.
    func offItem(of kind: AccessKind) -> PrivacyAccess.Item?
    /// Where an optional permission stands (see `OptionalAccess`). The ten above are `state(of: AccessKind)`.
    func state(of access: OptionalAccess) -> OptionalAccessState
    /// Asks for an optional permission. Only Allow in the Features pane and Grant in Privacy get here.
    func request(_ access: OptionalAccess) async
}

extension AccessProviding {
    func reload() async {}
    func offItem(of kind: AccessKind) -> PrivacyAccess.Item? { nil }
    func state(of access: OptionalAccess) -> OptionalAccessState { .notAsked }
    func request(_ access: OptionalAccess) async {}
}

/// The real Mac. States come from `PrivacyAccess.current()`; requests use the app's own paths. Nothing here runs until the person
/// presses a button that asks.
@MainActor
final class LiveAccess: AccessProviding {
    private let agenda: AgendaMonitor
    private let bluetooth: BluetoothAccess
    private let transfers: TransferMonitor
    private let defaults: UserDefaults
    /// Briefly taps a process so macOS shows the System Audio Recording prompt. Set by the Mixer; without it, asking only records that
    /// it was asked.
    var systemAudioProbe: (() async -> Void)?

    init(
        agenda: AgendaMonitor, bluetooth: BluetoothAccess, transfers: TransferMonitor, defaults: UserDefaults = .standard
    ) {
        self.agenda = agenda
        self.bluetooth = bluetooth
        self.transfers = transfers
        self.defaults = defaults
    }

    func state(of kind: AccessKind) -> PrivacyAccess.State {
        let rows = PrivacyAccess.current(defaults: defaults)
        func row(_ id: String) -> PrivacyAccess.State { rows.first { $0.id == id }?.state ?? .notAsked }
        if kind == .microphone {
            // Voice notes need the microphone and speech recognition: allowed only when both are, asked again while either isn't.
            let both = [row("microphone"), row("speech")]
            HotkeyLog.accessLogger.info("microphone=\(both[0].rawValue, privacy: .public) speech=\(both[1].rawValue, privacy: .public)")
            if both.allSatisfy({ $0 == .allowed }) { return .allowed }
            return both.contains(.notAsked) ? .notAsked : .denied
        }
        return row(kind.rawValue)
    }

    func state(of access: OptionalAccess) -> OptionalAccessState {
        OptionalAccessRecord.state(of: access, defaults: defaults)
    }

    func request(_ access: OptionalAccess) async {
        OptionalAccessRecord.record(.asked, for: access, defaults: defaults)
        switch access {
        case .systemAudio: await systemAudioProbe?()
        }
    }

    func offItem(of kind: AccessKind) -> PrivacyAccess.Item? {
        guard kind == .microphone else { return nil }
        let rows = PrivacyAccess.current(defaults: defaults)
        // Name the one that is off: the Microphone first, and Speech Recognition when the Microphone is on.
        let off = rows.filter { ["microphone", "speech"].contains($0.id) && $0.state != .allowed }
        return off.first.map { PrivacyAccess.Item(title: $0.title, settingsURL: $0.settingsURL) }
    }

    func request(_ kind: AccessKind) async -> Bool {
        switch kind {
        case .calendars: return await agenda.requestAccess(to: .event)
        case .reminders: return await agenda.requestAccess(to: .reminder)
        case .bluetooth: return await bluetooth.request()
        case .downloads:
            // Listing the folder is what makes macOS ask, and the answer can't be read back except by whether the listing worked.
            AccessAsked.mark(.downloads, defaults: defaults)
            let readable = await Task.detached { PrivacyAccess.downloadsFolderIsReadable() }.value
            if readable { transfers.start() }
            return readable
        case .camera:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            return microphone && speech
        case .screenRecording:
            AccessAsked.mark(.screenRecording, defaults: defaults)
            return CGRequestScreenCaptureAccess()
        case .accessibility:
            AccessAsked.mark(.accessibility, defaults: defaults)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        case .focus:
            return await withCheckedContinuation { continuation in
                INFocusStatusCenter.default.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        case .automation:
            return await requestAutomation()
        }
    }

    func reload() async {
        let defaults = defaults
        await Task.detached { AutomationAccess.read(defaults: defaults) }.value
    }

    /// Asks to control Music and Spotify. macOS can only ask about a running app, so with neither open, Music is opened hidden
    /// first, and left running. True when one said yes.
    private func requestAutomation() async -> Bool {
        func isRunning(_ id: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }
        if !AutomationAccess.bundleIDs.contains(where: isRunning) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            let music = URL(fileURLWithPath: "/System/Applications/Music.app")
            _ = try? await NSWorkspace.shared.openApplication(at: music, configuration: configuration)
            for _ in 0..<50 where !isRunning("com.apple.Music") { try? await Task.sleep(for: .milliseconds(100)) }
            // A moment for it to start answering Apple events.
            try? await Task.sleep(for: .milliseconds(500))
        }
        let defaults = defaults
        await Task.detached {
            var statuses: [String: OSStatus] = [:]
            for id in AutomationAccess.bundleIDs where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                statuses[id] = AutomationAccess.status(of: id, asking: true)
            }
            AutomationAccess.store(statuses, defaults: defaults)
        }.value
        return AutomationAccess.cachedState(defaults: defaults) == .allowed
    }
}

/// Where each permission stands for the guide and Settings, and what asking for one does.
@MainActor
@Observable
final class AccessModel {
    private(set) var states: [AccessKind: PrivacyAccess.State]
    /// The permission whose system prompt is showing.
    private(set) var asking: AccessKind?
    /// Where each optional permission stands.
    private(set) var optionalStates: [OptionalAccess: OptionalAccessState]
    /// The optional permission whose system prompt is showing.
    private(set) var askingOptional: OptionalAccess?

    @ObservationIgnored private let provider: AccessProviding
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let onBluetoothAllowed: () -> Void
    /// What was allowed in this run. EventKit can still say "not determined" for a moment after a grant, so a yes from a request
    /// stands until the system says no.
    @ObservationIgnored private var grantedThisSession: Set<AccessKind> = []

    init(provider: AccessProviding, settings: AppSettings, onBluetoothAllowed: @escaping () -> Void) {
        self.provider = provider
        self.settings = settings
        self.onBluetoothAllowed = onBluetoothAllowed
        states = Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, provider.state(of: $0)) })
        optionalStates = Dictionary(uniqueKeysWithValues: OptionalAccess.allCases.map { ($0, provider.state(of: $0)) })
    }

    // MARK: Optional access (never part of the setup gate)

    func state(of access: OptionalAccess) -> OptionalAccessState { optionalStates[access] ?? .notAsked }

    /// The optional permissions a feature still has to ask for.
    func optionalAccessToAsk(for feature: Feature) -> [OptionalAccess] {
        feature.optionalAccess.filter { state(of: $0) == .notAsked }
    }

    /// Asks for one optional permission, once. The system prompt appears only from here.
    func allow(_ access: OptionalAccess) async {
        guard asking == nil, askingOptional == nil, state(of: access) == .notAsked else { return }
        askingOptional = access
        await provider.request(access)
        askingOptional = nil
        readOptional()
    }

    private func readOptional() {
        let fresh = Dictionary(uniqueKeysWithValues: OptionalAccess.allCases.map { ($0, provider.state(of: $0)) })
        if fresh != optionalStates { optionalStates = fresh }
    }

    func state(of kind: AccessKind) -> PrivacyAccess.State { states[kind] ?? .notAsked }

    var allAllowed: Bool { AccessKind.allCases.allSatisfy { state(of: $0) == .allowed } }

    /// The permissions there is nothing left to ask. The guide leaves their steps out.
    /// For Microphone: whether it is the microphone or speech recognition that is off.
    func offItem(of kind: AccessKind) -> PrivacyAccess.Item? { provider.offItem(of: kind) }

    var allowed: Set<AccessKind> {
        Set(AccessKind.allCases.filter { state(of: $0) == .allowed })
    }

    /// The permissions that aren't allowed yet, in `AccessKind` order.
    var missing: [AccessKind] { AccessKind.allCases.filter { state(of: $0) != .allowed } }

    private func read(_ kind: AccessKind) -> PrivacyAccess.State {
        let read = provider.state(of: kind)
        return grantedThisSession.contains(kind) && read != .denied ? .allowed : read
    }

    private func readAll() -> [AccessKind: PrivacyAccess.State] {
        Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, read($0)) })
    }

    /// Reads every state again: after a system prompt closes, and when the person comes back from System Settings. What can only be
    /// read off the main actor (Automation) follows a moment later.
    func refresh() {
        readOptional()
        apply(readAll())
        Task { await reloadSlowReads() }
    }

    /// Asks for one permission. A grant also turns on the feature it serves, so the permission and the choice are one step;
    /// a denial changes nothing (macOS answers no at once from then on, so a denied row offers System Settings instead).
    func allow(_ kind: AccessKind) async {
        guard asking == nil, state(of: kind) == .notAsked else { return }
        asking = kind
        let granted = await provider.request(kind)
        asking = nil
        if granted {
            grantedThisSession.insert(kind)
            switch kind {
            case .calendars: if !settings.showsCalendar { settings.showsCalendar = true }
            case .reminders: if !settings.showsReminders { settings.showsReminders = true }
            case .bluetooth: onBluetoothAllowed()
            default: break
            }
        }
        apply(readAll())
        await reloadSlowReads()
    }

    /// Reads every state again, the slow ones too, and returns once they are in.
    func refreshed() async {
        readOptional()
        apply(readAll())
        await reloadSlowReads()
    }

    private func apply(_ fresh: [AccessKind: PrivacyAccess.State]) {
        if fresh != states { states = fresh }
    }

    private func reloadSlowReads() async {
        await provider.reload()
        apply(readAll())
    }
}

/// The one model Settings → Privacy asks through, made by the app at launch.
@MainActor
enum AccessCenter {
    static var model: AccessModel?
}

/// Quits and opens MacIsland again, which Screen Recording needs before it takes effect.
@MainActor
enum AppRelaunch {
    /// Lets go of what the new copy needs at once: the global shortcuts. The new copy starts before this one exits, and a hot key
    /// still held here would refuse to register there.
    static var beforeRelaunch: (() -> Void)?

    static func relaunch() {
        beforeRelaunch?()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
