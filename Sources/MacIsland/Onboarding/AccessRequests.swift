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

    /// Whether the system says nothing about this one until it is used: there is no "not asked yet" to read.
    var stateIsHidden: Bool {
        switch self {
        case .downloads, .automation, .screenRecording, .accessibility: true
        default: false
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

/// Which permissions MacIsland has asked for, for the ones the system won't say. Downloads can't be read without asking;
/// Screen Recording, Accessibility, and Automation can't tell "never asked" from "off". Kept in `UserDefaults`; the guide's
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
}

/// The real Mac. States come from `PrivacyAccess.current()`; requests use the app's own paths. Nothing here runs until the person
/// presses a button that asks.
@MainActor
final class LiveAccess: AccessProviding {
    private let agenda: AgendaMonitor
    private let bluetooth: BluetoothAccess
    private let transfers: TransferMonitor
    private let defaults: UserDefaults

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
            if both.allSatisfy({ $0 == .allowed }) { return .allowed }
            return both.contains(.notAsked) ? .notAsked : .denied
        }
        return row(kind.rawValue)
    }

    func request(_ kind: AccessKind) async -> Bool {
        switch kind {
        case .calendars: return await agenda.requestAccess(to: .event)
        case .reminders: return await agenda.requestAccess(to: .reminder)
        case .bluetooth: return await bluetooth.request()
        case .downloads:
            // Listing the folder is what makes macOS ask, and the answer can't be read back except by whether the listing worked.
            AccessAsked.mark(.downloads, defaults: defaults)
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            let readable = await Task.detached {
                downloads.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } != nil
            }.value
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
            AccessAsked.mark(.automation, defaults: defaults)
            return await Self.requestAutomation()
        }
    }

    /// Asks to control Music and Spotify, for whichever is running (macOS can only ask about a running app). True when one
    /// said yes.
    private static func requestAutomation() async -> Bool {
        await Task.detached {
            var allowed = false
            for bundleID in ["com.apple.Music", "com.spotify.client"] {
                guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { continue }
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc!, typeWildCard, typeWildCard, true)
                if status == noErr { allowed = true }
            }
            return allowed
        }.value
    }
}

/// Where each permission stands for the guide and Settings, and what asking for one does.
@MainActor
@Observable
final class AccessModel {
    private(set) var states: [AccessKind: PrivacyAccess.State]
    /// The permission whose system prompt is showing.
    private(set) var asking: AccessKind?

    @ObservationIgnored private let provider: AccessProviding
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let onBluetoothAllowed: () -> Void

    init(provider: AccessProviding, settings: AppSettings, onBluetoothAllowed: @escaping () -> Void) {
        self.provider = provider
        self.settings = settings
        self.onBluetoothAllowed = onBluetoothAllowed
        states = Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, provider.state(of: $0)) })
    }

    func state(of kind: AccessKind) -> PrivacyAccess.State { states[kind] ?? .notAsked }

    var allAllowed: Bool { AccessKind.allCases.allSatisfy { state(of: $0) == .allowed } }

    /// The permissions there is nothing left to ask: allowed, or asked once when the system won't say more. The guide leaves
    /// their steps out.
    var settled: Set<AccessKind> {
        Set(AccessKind.allCases.filter { [.allowed, .asked].contains(state(of: $0)) })
    }

    /// Reads every state again: after a system prompt closes, and when the person comes back from System Settings.
    func refresh() {
        let fresh = Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, provider.state(of: $0)) })
        if fresh != states { states = fresh }
    }

    /// Asks for one permission. A grant also turns on the feature it serves, so the permission and the choice are one step;
    /// a denial changes nothing (macOS answers no at once from then on, so a denied row offers System Settings instead).
    func allow(_ kind: AccessKind) async {
        guard asking == nil, state(of: kind) == .notAsked else { return }
        asking = kind
        let granted = await provider.request(kind)
        asking = nil
        if granted {
            switch kind {
            case .calendars: if !settings.showsCalendar { settings.showsCalendar = true }
            case .reminders: if !settings.showsReminders { settings.showsReminders = true }
            case .bluetooth: onBluetoothAllowed()
            default: break
            }
        }
        refresh()
    }

    /// Every permission still never asked, in `AccessKind` order, one after another. Skip uses it.
    func requestAllPending() async {
        for kind in AccessKind.allCases where state(of: kind) == .notAsked { await allow(kind) }
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
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
