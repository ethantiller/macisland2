import Foundation

/// A part of MacIsland that can be switched off entirely. The raw value is stored: add cases, never rename one.
enum Feature: String, CaseIterable, Identifiable {
    // Modules: pages of the open island.
    case music, clock, reminders, tools, shelf, clipboard, notes, agents
    // Island extensions: things that add to the island without a page of their own.
    case calendar, weather, volumeHUD, mixer, system, downloads, chooseActivity, notifications

    enum Group: String, CaseIterable {
        case modules = "Modules"
        case extensions = "Island Extensions"
    }

    var id: Self { self }

    var group: Group {
        switch self {
        case .music, .clock, .reminders, .tools, .shelf, .clipboard, .notes, .agents: .modules
        case .calendar, .weather, .volumeHUD, .mixer, .system, .downloads, .chooseActivity, .notifications: .extensions
        }
    }

    var title: String {
        switch self {
        case .music: "Music"
        case .clock: "Clock"
        case .reminders: "Reminders"
        case .tools: "Tools"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .notes: "Notes"
        case .agents: "AI Agents"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .volumeHUD: "Volume HUD"
        case .mixer: "Mixer"
        case .system: "System"
        case .downloads: "Downloads in the Shelf"
        case .chooseActivity: "Choose the Activity"
        case .notifications: "Notifications"
        }
    }

    /// One line: what it gives.
    var summary: String {
        switch self {
        case .music: "What is playing, with controls and synced lyrics."
        case .clock: "Timer, stopwatch, and Pomodoro."
        case .reminders: "Your open reminders, and the ones that are due."
        case .tools: "Keep Awake, Ring Light, Mirror, and the other tools."
        case .shelf: "A place to drop files, and AirDrop."
        case .clipboard: "Recent copies, kept in memory, in the Shelf."
        case .notes: "Quick notes, voice notes, and snippets."
        case .agents: "See when Claude Code or Codex is working."
        case .calendar: "Meetings in Up Next and Today, and a banner before one starts."
        case .weather: "The weather for your city."
        case .volumeHUD: "The island\u{2019}s volume indicator instead of the system\u{2019}s."
        case .mixer: "Each app\u{2019}s volume and where it plays."
        case .system: "A Home card with CPU, memory, battery, and how hot the Mac is."
        case .downloads: "Recent downloads, and the ones still arriving."
        case .chooseActivity: "Choose which live activity leads the closed island."
        case .notifications: "Preview notifications in the island, and keep an inbox."
        }
    }

    var systemImage: String {
        switch self {
        case .music: "music.note"
        case .clock: "timer"
        case .reminders: "checklist"
        case .tools: "square.grid.2x2"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .notes: "note.text"
        case .agents: "sparkles"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .volumeHUD: "speaker.wave.2"
        case .mixer: "slider.vertical.3"
        case .system: "cpu"
        case .downloads: "arrow.down.circle"
        case .chooseActivity: "rectangle.on.rectangle"
        case .notifications: "bell"
        }
    }

    /// Added after the catalog: off until switched on.
    var isNew: Bool {
        switch self {
        case .agents, .mixer, .system, .downloads, .chooseActivity, .notifications: true
        default: false
        }
    }

    /// The page of the open island this switches, if it has one of its own. The clipboard is a Shelf segment, and the extensions
    /// have none.
    var module: IslandModule? {
        switch self {
        case .music: .media
        case .clock: .clock
        case .reminders: .reminders
        case .tools: .tools
        case .shelf: .shelf
        case .notes: .notes
        case .agents: .agents
        default: nil
        }
    }

    /// What it costs while the island is closed.
    var cost: FeatureCost {
        switch self {
        case .music, .shelf, .volumeHUD, .agents, .mixer, .notifications: .listens
        case .reminders, .calendar: .checks(every: "30 seconds")
        case .clipboard: .checks(every: "second")
        case .weather: .checks(every: "30 minutes")
        case .clock, .tools, .notes, .system, .downloads, .chooseActivity: .nothing
        }
    }

    /// What a fresh install has: the features that existed before the catalog, except the volume HUD, which has always been off
    /// until turned on. Calendar is on in the sense of the presets, but its switch is `showsCalendar`, which the guide turns on
    /// when Calendars is allowed (nothing asks at launch), so a store the guide hasn't reached has it off.
    var isOnByDefault: Bool { !isNew && self != .volumeHUD }

    /// The features whose code exists in this build. A new feature's package adds its case: until then its switch does nothing and
    /// the Features pane doesn't list it.
    static let built: Set<Feature> = [
        .music, .clock, .reminders, .tools, .shelf, .clipboard, .notes, .calendar, .weather, .volumeHUD,
        .system, .agents, .mixer, .chooseActivity,
    ]

    var isBuilt: Bool { Self.built.contains(self) }

    /// The feature that switches a page of the island. Home has none: it is always on, so the strip is never empty.
    static func module(for module: IslandModule) -> Feature? {
        allCases.first { $0.module == module }
    }
}

/// What a feature costs while the island is closed, in words (the Features pane shows them).
enum FeatureCost: Equatable {
    case nothing
    case listens
    case checks(every: String)

    var words: String {
        switch self {
        case .nothing: "Nothing runs while the island is closed"
        case .listens: "Listens for changes, no timers"
        case .checks(let every): "Checks every \(every)"
        }
    }
}

/// A starting point: every feature set at once.
enum FeaturePreset: String, CaseIterable, Identifiable {
    case minimal, everyday, everything

    var id: Self { self }

    var title: String {
        switch self {
        case .minimal: "Minimal"
        case .everyday: "Everyday"
        case .everything: "Everything"
        }
    }

    var features: Set<Feature> {
        switch self {
        case .minimal: [.music, .clock, .shelf, .calendar]
        case .everyday: Set(Feature.allCases.filter(\.isOnByDefault))
        case .everything: Set(Feature.allCases)
        }
    }
}
