import Foundation

/// One thing a person can look for in Settings: where it is, what it is called, and what else they might type to find it.
struct SettingsSearchEntry: Identifiable, Equatable {
    let pane: SettingsPane
    let title: String
    /// Other words for it.
    var keywords: [String] = []
    /// The part of the pane to bring into view (`SettingsAnchor`), or nil for the top.
    var anchor: String?

    var id: String { "\(pane.rawValue)/\(title)" }
}

/// Names for the parts of a pane that search can scroll to. A pane puts `.id(...)` on the section with the same name.
enum SettingsAnchor {
    static let shortcut = "general.shortcut"
    static let input = "general.input"
    static let yourSettings = "general.settings"
    static let guide = "general.guide"
    static let menuBar = "tabs.menubar"
    static let widgets = "home.widgets"
    static let layout = "home.layout"
    static let upNext = "home.upnext"
    static let weather = "home.weather"
    static let files = "shelf.files"
    static let clipboard = "shelf.clipboard"
    static let music = "media.music"
    static let lyrics = "media.lyrics"
    static let pomodoro = "clock.pomodoro"
    static let toolsRow = "tools.row"
    static let rowOrder = "tools.roworder"
    static let interruptions = "notifications.interruptions"
    static let power = "notifications.power"
    static let devices = "notifications.devices"
    static let yourDay = "notifications.day"
    static let storage = "notifications.storage"
    static let leavesThisMac = "privacy.leaves"
    static let runs = "privacy.runs"
    static let access = "privacy.access"
}

/// Finding a setting by what it is called. Pure, so it is tested.
enum SettingsSearch {
    /// Every setting that has a place in the panes, in the order the panes show them. Keep it in step with the panes: a new setting
    /// gets an entry here.
    static let entries: [SettingsSearchEntry] =
        SettingsPane.allCases.map { SettingsSearchEntry(pane: $0, title: $0.title) } + [
            // General
            .init(pane: .general, title: "Launch at Login", keywords: ["startup", "start", "open at login", "boot"]),
            .init(
                pane: .general, title: "Shortcut",
                keywords: ["hotkey", "keyboard", "keys", "open the island", "record"],
                anchor: SettingsAnchor.shortcut),
            .init(
                pane: .general, title: "Peek on Hover", keywords: ["hover", "mouse", "swell", "preview"],
                anchor: SettingsAnchor.input),
            .init(
                pane: .general, title: "Swipe to Open and Switch Tabs",
                keywords: ["swipe", "trackpad", "gesture", "magic mouse", "scroll"], anchor: SettingsAnchor.input),
            .init(
                pane: .general, title: "Show the Island On",
                keywords: ["display", "screen", "monitor", "external", "primary", "notch"], anchor: SettingsAnchor.input
            ),
            .init(
                pane: .general, title: "Welcome Guide",
                keywords: ["onboarding", "tutorial", "intro", "help", "getting started", "gestures"],
                anchor: SettingsAnchor.guide),
            .init(
                pane: .general, title: "Settings Tour", keywords: ["tour", "tutorial", "help", "walkthrough", "tips"],
                anchor: SettingsAnchor.guide),
            .init(
                pane: .general, title: "Export Settings",
                keywords: ["save", "backup", "file", "json", "share"], anchor: SettingsAnchor.yourSettings),
            .init(
                pane: .general, title: "Import Settings", keywords: ["restore", "load", "file", "json"],
                anchor: SettingsAnchor.yourSettings),
            .init(
                pane: .general, title: "Reset All Settings", keywords: ["defaults", "factory", "erase", "clear"],
                anchor: SettingsAnchor.yourSettings),
            // Tabs
            .init(
                pane: .tabs, title: "Left of the Notch",
                keywords: ["tabs", "order", "arrange", "strip", "drag", "reorder"]),
            .init(pane: .tabs, title: "Right of the Notch", keywords: ["tabs", "order", "arrange", "strip", "side"]),
            .init(pane: .tabs, title: "Turn a Tab On or Off", keywords: ["hide", "show", "tab", "enable", "disable"]),
            .init(
                pane: .tabs, title: "Menu Bar",
                keywords: ["module", "icon", "window", "menu bar", "tear off", "floating"],
                anchor: SettingsAnchor.menuBar),
            // Home
            .init(
                pane: .home, title: "Add Widgets", keywords: ["widget", "gallery", "new", "custom", "shortcut"],
                anchor: SettingsAnchor.widgets),
            .init(
                pane: .home, title: "Widget Size",
                keywords: ["resize", "bigger", "smaller", "columns", "rows", "grid", "corner"],
                anchor: SettingsAnchor.widgets),
            .init(
                pane: .home, title: "Presets",
                keywords: ["layout", "everyday", "focus", "listening", "minimal", "dashboard", "save", "saved"],
                anchor: SettingsAnchor.layout),
            .init(
                pane: .home, title: "Save Layout",
                keywords: ["preset", "name", "keep", "configuration", "remove", "delete"],
                anchor: SettingsAnchor.layout),
            .init(
                pane: .home, title: "Export Home Layout", keywords: ["file", "share", "macislandhome"],
                anchor: SettingsAnchor.layout),
            .init(
                pane: .home, title: "Import Home Layout", keywords: ["file", "load", "macislandhome"],
                anchor: SettingsAnchor.layout),
            .init(
                pane: .home, title: "Reset Home to Everyday", keywords: ["default", "layout"],
                anchor: SettingsAnchor.layout),
            .init(
                pane: .home, title: "Calendar Events",
                keywords: ["up next", "meetings", "calendar", "outlook", "google", "exchange"],
                anchor: SettingsAnchor.upNext),
            .init(
                pane: .home, title: "Due Reminders", keywords: ["up next", "reminders", "tasks"],
                anchor: SettingsAnchor.upNext),
            .init(
                pane: .home, title: "Internet Accounts",
                keywords: ["calendar", "outlook", "google", "exchange", "accounts"],
                anchor: SettingsAnchor.upNext),
            .init(
                pane: .home, title: "Weather City",
                keywords: ["weather", "city", "location", "temperature", "open-meteo"],
                anchor: SettingsAnchor.weather),
            // Shelf
            .init(
                pane: .shelf, title: "When You Drag a File",
                keywords: ["drop", "airdrop", "target", "shelf only", "drag"],
                anchor: SettingsAnchor.files),
            .init(
                pane: .shelf, title: "Add New Screenshots to the Shelf", keywords: ["screenshot", "capture", "screen"],
                anchor: SettingsAnchor.files),
            .init(
                pane: .shelf, title: "Remove Files from the Shelf",
                keywords: ["retention", "clean", "delete", "expire", "day", "week"], anchor: SettingsAnchor.files),
            .init(
                pane: .shelf, title: "Clipboard History",
                keywords: ["copy", "paste", "items", "pasteboard", "limit", "off"], anchor: SettingsAnchor.clipboard),
            // Media
            .init(
                pane: .media, title: "Show Music Beside the Notch",
                keywords: ["compact", "now playing", "collapsed", "art"],
                anchor: SettingsAnchor.music),
            .init(
                pane: .media, title: "Synced Lyrics", keywords: ["lrc", "lrclib", "words", "song", "karaoke"],
                anchor: SettingsAnchor.lyrics),
            // Clock
            .init(
                pane: .clock, title: "Focus Length",
                keywords: ["pomodoro", "work", "session", "minutes", "25", "timer"], anchor: SettingsAnchor.pomodoro),
            .init(
                pane: .clock, title: "Short Break",
                keywords: ["pomodoro", "rest", "minutes", "5", "timer"], anchor: SettingsAnchor.pomodoro),
            .init(
                pane: .clock, title: "Long Break",
                keywords: ["pomodoro", "rest", "minutes", "15", "timer"], anchor: SettingsAnchor.pomodoro),
            .init(
                pane: .clock, title: "Sessions Before Long Break",
                keywords: ["pomodoro", "cycle", "rounds", "focus", "four", "4"], anchor: SettingsAnchor.pomodoro),
            // Tools
            .init(
                pane: .tools, title: "Tools in the Row",
                keywords: ["pin", "pinned", "4", "6", "8", "count", "how many"],
                anchor: SettingsAnchor.toolsRow),
            .init(
                pane: .tools, title: "Row Order", keywords: ["reorder", "drag", "move", "pin", "unpin"],
                anchor: SettingsAnchor.rowOrder),
            // Notifications
            .init(
                pane: .notifications, title: "Quiet in Focus", keywords: ["do not disturb", "dnd", "silence", "mute"],
                anchor: SettingsAnchor.interruptions),
            .init(
                pane: .notifications, title: "Charging",
                keywords: ["power", "plug", "battery", "alert", "bolt"], anchor: SettingsAnchor.power),
            .init(
                pane: .notifications, title: "Full Charge", keywords: ["power", "battery", "100", "alert"],
                anchor: SettingsAnchor.power),
            .init(
                pane: .notifications, title: "Full Charge Alert",
                keywords: ["level", "percent", "battery", "80", "90"],
                anchor: SettingsAnchor.power),
            .init(
                pane: .notifications, title: "Low Battery", keywords: ["power", "alert", "warning", "20"],
                anchor: SettingsAnchor.power),
            .init(
                pane: .notifications, title: "Headphones",
                keywords: ["airpods", "bluetooth", "beats", "devices", "banner"],
                anchor: SettingsAnchor.devices),
            .init(
                pane: .notifications, title: "Drives",
                keywords: ["disk", "usb", "volume", "eject", "external", "devices"],
                anchor: SettingsAnchor.devices),
            .init(
                pane: .notifications, title: "Personal Hotspot", keywords: ["tethering", "wifi", "devices", "network"],
                anchor: SettingsAnchor.devices),
            .init(
                pane: .notifications, title: "Unlocked", keywords: ["touch id", "lock", "login", "devices"],
                anchor: SettingsAnchor.devices),
            .init(
                pane: .notifications, title: "Meetings",
                keywords: ["calendar", "event", "join", "zoom", "teams", "your day"],
                anchor: SettingsAnchor.yourDay),
            .init(
                pane: .notifications, title: "Due Reminders", keywords: ["reminders", "tasks", "your day"],
                anchor: SettingsAnchor.yourDay),
            .init(
                pane: .notifications, title: "Rain Soon", keywords: ["weather", "forecast", "umbrella", "your day"],
                anchor: SettingsAnchor.yourDay),
            .init(
                pane: .notifications, title: "Downloads", keywords: ["saved", "browser", "file", "storage"],
                anchor: SettingsAnchor.storage),
            .init(
                pane: .notifications, title: "Low Disk Space", keywords: ["storage", "full", "space", "gigabytes"],
                anchor: SettingsAnchor.storage),
            // Privacy
            .init(
                pane: .privacy, title: "What Leaves This Mac",
                keywords: ["network", "internet", "weather", "lyrics", "data", "analytics", "servers", "sent"],
                anchor: SettingsAnchor.leavesThisMac),
            .init(
                pane: .privacy, title: "Things MacIsland Runs",
                keywords: ["programs", "commands", "shortcuts", "scripts", "processes", "widgets"],
                anchor: SettingsAnchor.runs),
            .init(
                pane: .privacy, title: "Access",
                keywords: [
                    "permissions", "calendar", "reminders", "camera", "microphone", "accessibility", "screen recording",
                    "bluetooth", "system settings",
                ], anchor: SettingsAnchor.access),
        ]

    /// Lowercase and without accents, so "cafe" finds "Café".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The entries that match every word of `query`, best first: a title that starts with a word, then one that contains it, then
    /// another word for it, then the pane it is on. Ties keep the panes' order. Nothing for an empty query.
    static func results(for query: String, in entries: [SettingsSearchEntry] = entries) -> [SettingsSearchEntry] {
        let words = normalized(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        let scored: [(entry: SettingsSearchEntry, score: Int, order: Int)] = entries.enumerated().compactMap {
            order, entry in
            let title = normalized(entry.title)
            let keywords = entry.keywords.map(normalized)
            let pane = normalized(entry.pane.title)
            var total = 0
            for word in words {
                let score = Self.score(word, title: title, keywords: keywords, pane: pane)
                guard score > 0 else { return nil }
                total += score
            }
            return (entry, total, order)
        }
        return scored.sorted { ($1.score, $0.order) < ($0.score, $1.order) }.map(\.entry)
    }

    /// How well one word matches: 0 is not at all.
    private static func score(_ word: String, title: String, keywords: [String], pane: String) -> Int {
        func startsAWord(_ text: String) -> Bool {
            text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(word) }
        }
        if title.hasPrefix(word) { return 6 }
        if startsAWord(title) { return 5 }
        if title.contains(word) { return 3 }
        if keywords.contains(where: startsAWord) { return 2 }
        if keywords.contains(where: { $0.contains(word) }) { return 1 }
        if pane.hasPrefix(word) { return 1 }
        return 0
    }
}
