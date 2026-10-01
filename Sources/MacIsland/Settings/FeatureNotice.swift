import SwiftUI

/// What switching a feature off will stop, in words, for the line under its row. Nil when nothing live is affected.
enum FeatureNotice {
    @MainActor
    static func whatStops(_ feature: Feature, features: IslandFeatures) -> String? {
        switch feature {
        case .clock:
            var running: [String] = []
            if features.timer.isActive { running.append("timer") }
            if features.stopwatch.isActive { running.append("stopwatch") }
            if features.pomodoro.isActive { running.append("Pomodoro") }
            return sentence(running, one: "The running %@ was stopped.", many: "The running %@ were stopped.")
        case .tools:
            var on: [String] = []
            if features.keepAwake.isOn { on.append("Keep Awake") }
            if features.ringLight.isOn { on.append("Ring Light") }
            if features.mirror.isOn { on.append("Mirror") }
            if features.keyboardCleaner.isLocked { on.append("Clean Keys") }
            return sentence(on, one: "%@ was turned off.", many: "%@ were turned off.")
        case .notes:
            return features.voice.isRecording ? "The voice note was saved." : nil
        case .clipboard:
            return features.clipboard.entries.isEmpty ? nil : "The clipboard history was cleared."
        case .music:
            return features.nowPlaying.state.isPlaying ? "The player keeps playing; MacIsland stops listening to it." : nil
        default:
            return nil
        }
    }

    private static func sentence(_ names: [String], one: String, many: String) -> String? {
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and))
        return String(format: names.count == 1 ? one : many, list)
    }
}

extension FeaturePreset {
    /// What choosing the preset does, for the confirmation: what it turns on, and that the rest go off and nothing is deleted.
    var confirmation: String {
        let built = Feature.allCases.filter(\.isBuilt)
        let on = built.filter { features.contains($0) }.map(\.title)
        let what =
            on.count == built.count
            ? "It turns every feature on."
            : "It turns on \(on.formatted(.list(type: .and))) and turns the rest off."
        return "\(what) Nothing is deleted: turning a feature back on brings its settings back."
    }
}

extension AppSettings {
    /// How many of the features this build has are on, for the line under the presets.
    var featureCount: (on: Int, of: Int) {
        let built = Feature.allCases.filter(\.isBuilt)
        return (built.filter(isOn).count, built.count)
    }
}

extension Feature {
    /// Where the feature lands on the island, for the preview while its row is chosen. Nil for one with nothing to show yet.
    var previewContext: PreviewContext? {
        switch self {
        case .music: PreviewContext(presentation: .expanded, tab: .media)
        case .clock: PreviewContext(presentation: .expanded, tab: .clock)
        case .reminders: PreviewContext(presentation: .expanded, tab: .reminders)
        case .tools: PreviewContext(presentation: .expanded, tab: .tools)
        case .notes: PreviewContext(presentation: .expanded, tab: .notes)
        case .shelf: PreviewContext(presentation: .compact, tab: .shelf, fileDrag: true)
        case .clipboard: PreviewContext(presentation: .expanded, tab: .shelf)
        case .calendar: PreviewContext(presentation: .banner, event: .meeting)
        case .weather: PreviewContext(presentation: .peek)
        case .volumeHUD: PreviewContext(presentation: .banner, showsVolume: true)
        case .agents, .mixer, .system, .downloads, .chooseActivity, .notifications: nil
        }
    }

    /// Other words for it, for search.
    var keywords: [String] {
        switch self {
        case .music: ["media", "now playing", "player", "lyrics", "spotify", "apple music"]
        case .clock: ["timer", "stopwatch", "pomodoro", "alarm"]
        case .reminders: ["tasks", "todo", "due", "checklist"]
        case .tools: ["keep awake", "ring light", "mirror", "clean keys", "shortcuts"]
        case .shelf: ["files", "drop", "airdrop", "drag", "screenshots", "storage"]
        case .clipboard: ["copy", "paste", "history", "pasteboard"]
        case .notes: ["note", "voice", "snippets", "write", "prompter"]
        case .agents: ["claude code", "codex", "ai", "tokens", "usage"]
        case .calendar: ["up next", "meetings", "events", "outlook", "google", "exchange", "banner"]
        case .weather: ["forecast", "temperature", "rain", "city"]
        case .volumeHUD: ["replace", "volume", "sound", "keys", "hud", "speaker", "mute", "accessibility"]
        case .mixer: ["volume", "per app", "boost", "sound", "output", "audio"]
        case .system: ["cpu", "memory", "battery", "temperature", "thermal"]
        case .downloads: ["shelf", "files", "arriving", "browser"]
        case .chooseActivity: ["peek", "pair", "live", "lead", "priority"]
        case .notifications: ["banner", "inbox", "mirror", "alerts", "messages"]
        }
    }
}
