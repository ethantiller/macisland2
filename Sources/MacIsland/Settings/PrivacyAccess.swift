import AVFoundation
import AppKit
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
        /// Asked once, and the system won't say what the answer was (Downloads, Automation).
        case asked = "Asked"
    }

    let id: String
    let title: String
    /// Why MacIsland wants it.
    let reason: String
    let state: State
    /// The System Settings pane's link.
    let settingsURL: URL

    /// `defaults` holds which permissions were asked for, for the ones the system won't say (`AccessAsked`).
    @MainActor
    static func current(defaults: UserDefaults = .standard) -> [PrivacyAccess] {
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
        /// What can't be read at all: not asked, then asked.
        func askedOnly(_ kind: AccessKind) -> State {
            AccessAsked.contains(kind, defaults: defaults) ? .asked : .notAsked
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
            // Downloads and Automation can't be read at all without asking.
            row(
                "downloads", "Downloads", "Progress while a file downloads", askedOnly(.downloads),
                pane: "Privacy_FilesAndFolders"),
            row("focus", "Focus", "Quiet in Focus", focus, pane: "Privacy_Focus"),
            row(
                "automation", "Automation", "Play, pause, and Favorite in Music and Spotify", askedOnly(.automation),
                pane: "Privacy_Automation"),
        ]
    }
}
