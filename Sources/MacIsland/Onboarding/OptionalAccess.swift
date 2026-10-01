import Foundation

/// A permission that only an optional feature needs. It isn't one of the ten the guide walks through (`AccessKind`), so it never
/// closes the setup gate: it is asked when the feature is switched on and the person presses Allow, and the island never asks.
enum OptionalAccess: String, CaseIterable, Identifiable {
    /// The Mixer's. macOS asks the first time a process tap starts.
    case systemAudio

    var id: Self { self }

    var title: String {
        switch self {
        case .systemAudio: "System Audio Recording"
        }
    }

    var symbol: String {
        switch self {
        case .systemAudio: "waveform"
        }
    }

    /// Why, in terms of what the person gets. One short line, for lists.
    var reason: String {
        switch self {
        case .systemAudio: "Per-app volume and output in the Mixer"
        }
    }

    /// The plain sentence the Features pane shows before the system prompt can appear.
    var explanation: String {
        switch self {
        case .systemAudio:
            "The Mixer changes each app\u{2019}s volume by passing its sound through MacIsland. macOS asks for System Audio Recording; nothing is recorded or kept."
        }
    }

    /// The feature this permission serves.
    var feature: Feature {
        switch self {
        case .systemAudio: .mixer
        }
    }

    /// The System Settings pane where it is turned back on.
    var settingsURL: URL? {
        switch self {
        case .systemAudio:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        }
    }

    /// For the Privacy pane: what uses it now.
    @MainActor
    func usage(settings: AppSettings) -> String {
        settings.isOn(feature)
            ? "Used by \(feature.title)"
            : "Nothing that is on uses it; you can turn it off in System Settings"
    }
}

extension Feature {
    /// The optional permissions the feature needs.
    var optionalAccess: [OptionalAccess] {
        OptionalAccess.allCases.filter { $0.feature == self }
    }
}

/// Where a permission with no public API to read stands. macOS has no call for System Audio Recording, so its state is evidence: not
/// asked until MacIsland has asked; then allowed once a tap has delivered sound, denied once a tap delivered only silence while its app
/// was playing, and asked (it can't be checked) in between.
enum OptionalAccessState: String, Equatable {
    case notAsked, asked, allowed, denied

    var words: String {
        switch self {
        case .notAsked: "Not Asked Yet"
        case .asked: "Can\u{2019}t Be Checked"
        case .allowed: "Allowed"
        case .denied: "Off"
        }
    }
}

/// The evidence, kept in `UserDefaults`: `access.optional` is a dictionary of the access to its state. It records an answer, not use,
/// so it is not an install-evidence key, and `make first-run` clears it.
enum OptionalAccessRecord {
    static let key = "access.optional"

    static func state(of access: OptionalAccess, defaults: UserDefaults = .standard) -> OptionalAccessState {
        let stored = defaults.dictionary(forKey: key) as? [String: String]
        return stored?[access.rawValue].flatMap(OptionalAccessState.init(rawValue:)) ?? .notAsked
    }

    /// Records what was seen. Asking never undoes an answer already seen, and does nothing unless the state changes.
    static func record(_ state: OptionalAccessState, for access: OptionalAccess, defaults: UserDefaults = .standard) {
        let current = Self.state(of: access, defaults: defaults)
        guard current != state, !(state == .asked && current != .notAsked) else { return }
        var stored = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        stored[access.rawValue] = state.rawValue
        defaults.set(stored, forKey: key)
    }
}
