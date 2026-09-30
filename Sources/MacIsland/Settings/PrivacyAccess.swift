import AVFoundation
import AppKit
import CoreBluetooth
import EventKit
import Speech

/// What each permission is set to, read without asking for anything.
struct PrivacyAccess: Identifiable, Equatable {
    enum State: String, Equatable {
        case allowed = "Allowed"
        case denied = "Off"
        case notAsked = "Not Asked Yet"
    }

    let id: String
    let title: String
    /// Why MacIsland wants it.
    let reason: String
    let state: State
    /// The System Settings pane's link.
    let settingsURL: URL

    @MainActor
    static func current() -> [PrivacyAccess] {
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
            row(
                "screen", "Screen Recording", "Record Screen",
                CGPreflightScreenCaptureAccess() ? .allowed : .denied, pane: "Privacy_ScreenCapture"),
            // Like Screen Recording, it can't tell "never asked" from "off".
            row(
                "accessibility", "Accessibility", "Clean Keys",
                KeyboardCleaner.hasAccess ? .allowed : .denied, pane: "Privacy_Accessibility"),
            row(
                "bluetooth", "Bluetooth", "Headphone batteries and the device switcher", bluetooth,
                pane: "Privacy_Bluetooth"),
        ]
    }
}
