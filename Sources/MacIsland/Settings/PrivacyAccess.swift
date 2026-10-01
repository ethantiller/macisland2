import AVFoundation
import AppKit
import ApplicationServices
import CoreBluetooth
import EventKit
import Intents
import Speech

/// What each permission is set to, read without asking for anything.
struct PrivacyAccess: Identifiable, Equatable {
    enum State: String, Equatable {
        case allowed = "Allowed"
        case denied = "Off"
        case notAsked = "Not Asked Yet"
    }

    /// One permission by name, with the pane that turns it on.
    struct Item: Equatable {
        let title: String
        let settingsURL: URL
    }

    let id: String
    let title: String
    /// Why MacIsland wants it.
    let reason: String
    let state: State
    /// The System Settings pane's link.
    let settingsURL: URL

    /// `defaults` holds which permissions were asked for, and the last answer for Automation. `downloadsReadable` lists the Downloads
    /// folder; it is asked only once Downloads has been asked for, because listing the folder is what makes macOS ask.
    @MainActor
    static func current(
        defaults: UserDefaults = .standard, downloadsReadable: () -> Bool = PrivacyAccess.downloadsFolderIsReadable
    ) -> [PrivacyAccess] {
        func row(_ id: String, _ title: String, _ reason: String, _ state: State, pane: String) -> PrivacyAccess {
            PrivacyAccess(
                id: id, title: title, reason: reason, state: state,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
        func event(_ type: EKEntityType) -> State {
            switch EKEventStore.authorizationStatus(for: type) {
            case .fullAccess: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        }
        func media(_ type: AVMediaType) -> State {
            switch AVCaptureDevice.authorizationStatus(for: type) {
            case .authorized: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        }
        let speech: State =
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        let bluetooth: State =
            switch CBManager.authorization {
            case .allowedAlways: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        let focus: State =
            switch INFocusStatusCenter.default.authorizationStatus {
            case .authorized: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        /// What the system can't tell "never asked" from "off": not asked until MacIsland has asked.
        func undecided(_ kind: AccessKind, granted: Bool) -> State {
            if granted { return .allowed }
            return AccessAsked.contains(kind, defaults: defaults) ? .denied : .notAsked
        }
        /// Downloads can't be read without asking, so it is not asked until MacIsland has asked. After that macOS never prompts
        /// again, and whether the folder lists is the answer.
        func downloads() -> State {
            guard AccessAsked.contains(.downloads, defaults: defaults) else { return .notAsked }
            return downloadsReadable() ? .allowed : .denied
        }
        return [
            row("calendars", "Calendars", "Up Next and meeting banners", event(.event), pane: "Privacy_Calendars"),
            row(
                "reminders", "Reminders", "The Reminders tab and due banners", event(.reminder),
                pane: "Privacy_Reminders"),
            row("camera", "Camera", "The Mirror", media(.video), pane: "Privacy_Camera"),
            row("microphone", "Microphone", "Voice notes", media(.audio), pane: "Privacy_Microphone"),
            row(
                "speech", "Speech Recognition", "Turning voice notes into text, on this Mac", speech,
                pane: "Privacy_SpeechRecognition"),
            // Screen Recording and Accessibility can't tell "never asked" from "off": not asked until MacIsland has asked.
            row(
                "screen", "Screen Recording", "Record Screen",
                undecided(.screenRecording, granted: CGPreflightScreenCaptureAccess()), pane: "Privacy_ScreenCapture"),
            row(
                "accessibility", "Accessibility", "Clean Keys",
                undecided(.accessibility, granted: KeyboardCleaner.hasAccess), pane: "Privacy_Accessibility"),
            row(
                "bluetooth", "Bluetooth", "Headphone batteries and the device switcher", bluetooth,
                pane: "Privacy_Bluetooth"),
            row(
                "downloads", "Downloads", "Progress while a file downloads", downloads(), pane: "Privacy_FilesAndFolders"),
            row("focus", "Focus", "Quiet in Focus", focus, pane: "Privacy_Focus"),
            // Automation is per app and can only be read while the app runs: the last answer is kept (`AutomationAccess`).
            row(
                "automation", "Automation", "Play, pause, and Favorite in Music and Spotify",
                AutomationAccess.cachedState(defaults: defaults), pane: "Privacy_Automation"),
        ]
    }

    /// Whether `~/Downloads` lists. A single directory listing, so the main actor can do it.
    static func downloadsFolderIsReadable() -> Bool {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return folder.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } != nil
    }
}

/// Automation: whether MacIsland may control Music and Spotify. macOS answers per app, and only while the app runs, so each app's
/// last known answer is kept in `UserDefaults` (`access.automation`: bundle id to "allowed" or "denied") for when it isn't.
enum AutomationAccess {
    static let bundleIDs = ["com.apple.Music", "com.spotify.client"]
    static let cacheKey = "access.automation"

    /// What `AEDeterminePermissionToAutomateTarget` returns.
    static let denied = OSStatus(errAEEventNotPermitted)
    static let wouldAsk = OSStatus(errAEEventWouldRequireUserConsent)
    static let notRunning = OSStatus(procNotFound)

    /// The cache after what was just read: a yes or no replaces the old answer, "would ask" forgets it (the person reset the
    /// permission), and an app that isn't running keeps what it had.
    static func updatedCache(statuses: [String: OSStatus], cache: [String: String]) -> [String: String] {
        var cache = cache
        for (id, status) in statuses {
            switch status {
            case noErr: cache[id] = "allowed"
            case denied: cache[id] = "denied"
            case wouldAsk: cache[id] = nil
            default: break
            }
        }
        return cache
    }

    /// Allowed when either app is; otherwise off when either is; otherwise not asked. `statuses` is what was just read, and the
    /// cache covers an app that isn't running.
    static func state(statuses: [String: OSStatus], cache: [String: String]) -> PrivacyAccess.State {
        let known = updatedCache(statuses: statuses, cache: cache)
        let answers = bundleIDs.compactMap { known[$0] }
        if answers.contains("allowed") { return .allowed }
        return answers.contains("denied") ? .denied : .notAsked
    }

    static func cachedState(defaults: UserDefaults) -> PrivacyAccess.State {
        state(statuses: [:], cache: defaults.dictionary(forKey: cacheKey) as? [String: String] ?? [:])
    }

    /// Reads each running app's answer without asking, and remembers it. Blocks, so not on the main actor.
    static func read(defaults: UserDefaults) {
        var statuses: [String: OSStatus] = [:]
        for id in bundleIDs where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            statuses[id] = status(of: id, asking: false)
        }
        store(statuses, defaults: defaults)
    }

    static func status(of bundleID: String, asking: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc!, typeWildCard, typeWildCard, asking)
    }

    static func store(_ statuses: [String: OSStatus], defaults: UserDefaults) {
        let cache = defaults.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        let updated = updatedCache(statuses: statuses, cache: cache)
        if updated != cache { defaults.set(updated, forKey: cacheKey) }
    }
}
