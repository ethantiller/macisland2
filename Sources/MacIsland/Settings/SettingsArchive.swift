import AppKit
import Foundation

/// Every personal choice in one file, to keep, move to another Mac, or share. Every field is optional, so a file from an
/// older MacIsland (with fewer) still reads. It never contains a command widget, going out or coming in.
struct SettingsArchive: Codable, Equatable {
    static let format = "MacIsland Settings"
    static let currentVersion = 2

    var format = SettingsArchive.format
    var version = SettingsArchive.currentVersion

    var openShortcut: StoredShortcut?
    var shelfShortcut: StoredShortcut?
    var peeksOnHover: Bool?
    var swipesEnabled: Bool?
    var islandDisplay: String?
    var leftTabs: [String]?
    var rightTabs: [String]?
    var menuBarModules: [String]?
    /// Home's layout, and the custom widgets on it, as in a Home file.
    var home: HomeArchive?
    var showsCalendar: Bool?
    var showsReminders: Bool?
    var showsTimeLeft: Bool?
    var countsDownToEveryEvent: Bool?
    var readsClaudeCode: Bool?
    var readsCodex: Bool?
    var showsAgentCompact: Bool?
    var agentFinishMinimum: Int?
    var agentLimitThreshold: Int?
    var showsLimitsLeft: Bool?
    var weatherCity: String?
    var dragTarget: String?
    var addsScreenshots: Bool?
    var shelfRetention: String?
    var clipboardLimit: Int?
    var shelfMode: String?
    var showsLyrics: Bool?
    var replacesVolumeHUD: Bool?
    var showsMusicCompact: Bool?
    var pinLimit: Int?
    var pinnedTools: [String]?
    /// Tools made from Shortcuts. A Shortcut's name is fine to export; the Shortcut itself is not.
    var shortcutTools: [ShortcutTool]?
    var quietDuringFocus: Bool?
    var fullChargeLevel: Int?
    var mutedEvents: [String]?
    var pomodoroFocus: Int?
    var pomodoroShortBreak: Int?
    var pomodoroLongBreak: Int?
    var pomodoroSessions: Int?
    /// Every feature's switch by raw value, written in full. A name this build doesn't know is skipped on reading.
    var features: [String: Bool]?

    enum ReadError: LocalizedError, Equatable {
        case notAnArchive, tooNew

        var errorDescription: String? {
            switch self {
            case .notAnArchive: "That isn\u{2019}t a MacIsland settings file."
            case .tooNew: "That file is from a newer MacIsland."
            }
        }
    }

    // MARK: Writing

    @MainActor
    static func make(from settings: AppSettings) -> SettingsArchive {
        var archive = SettingsArchive()
        archive.openShortcut = StoredShortcut(combo: settings.openShortcut)
        archive.shelfShortcut = StoredShortcut(combo: settings.shelfShortcut)
        archive.peeksOnHover = settings.peeksOnHover
        archive.swipesEnabled = settings.swipesEnabled
        archive.islandDisplay = settings.islandDisplay.rawValue
        archive.leftTabs = settings.leftTabs.map(\.rawValue)
        archive.rightTabs = settings.rightTabs.map(\.rawValue)
        archive.menuBarModules = settings.menuBarModules.map(\.rawValue)
        archive.home = HomeArchive.make(layout: settings.homeLayout, customs: settings.customWidgets)
        archive.showsCalendar = settings.showsCalendar
        archive.showsReminders = settings.showsReminders
        archive.showsTimeLeft = settings.showsTimeLeft
        archive.countsDownToEveryEvent = settings.countsDownToEveryEvent
        archive.readsClaudeCode = settings.readsClaudeCode
        archive.readsCodex = settings.readsCodex
        archive.showsAgentCompact = settings.showsAgentCompact
        archive.agentFinishMinimum = settings.agentFinishMinimum
        archive.agentLimitThreshold = settings.agentLimitThreshold
        archive.showsLimitsLeft = settings.showsLimitsLeft
        archive.weatherCity = settings.weatherCity
        archive.dragTarget = settings.dragTarget.rawValue
        archive.addsScreenshots = settings.addsScreenshots
        archive.shelfRetention = settings.shelfRetention.rawValue
        archive.clipboardLimit = settings.clipboardLimit
        archive.shelfMode = settings.shelfMode.rawValue
        archive.showsLyrics = settings.showsLyrics
        archive.replacesVolumeHUD = settings.replacesVolumeHUD
        archive.showsMusicCompact = settings.showsMusicCompact
        archive.pinLimit = settings.pinLimit.rawValue
        archive.pinnedTools = settings.pinnedTools.map(\.rawValue)
        archive.shortcutTools = settings.shortcutTools
        archive.quietDuringFocus = settings.quietDuringFocus
        archive.fullChargeLevel = settings.fullChargeLevel
        archive.mutedEvents = settings.mutedEvents.map(\.rawValue).sorted()
        archive.pomodoroFocus = settings.pomodoroFocus
        archive.pomodoroShortBreak = settings.pomodoroShortBreak
        archive.pomodoroLongBreak = settings.pomodoroLongBreak
        archive.pomodoroSessions = settings.pomodoroSessions
        archive.features = Dictionary(uniqueKeysWithValues: Feature.allCases.map { ($0.rawValue, settings.isOn($0)) })
        return archive
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Reading

    static func read(_ data: Data) throws -> SettingsArchive {
        guard let archive = try? JSONDecoder().decode(SettingsArchive.self, from: data), archive.format == format
        else { throw ReadError.notAnArchive }
        guard archive.version <= currentVersion else { throw ReadError.tooNew }
        return archive
    }

    /// One line for the confirmation: what is about to be replaced.
    func summary() -> String {
        var parts = ["Your settings"]
        if let home {
            let widgets = home.importPlan().widgets
            parts.append(widgets.isEmpty ? "your Home layout" : HomeArchive.summary(of: widgets).lowercased())
        }
        return parts.joined(separator: ", ") + " will be replaced. Command widgets are never imported."
    }
}

extension AppSettings {
    /// The choices in `archive`, checked and repaired one by one: a value that isn\u{2019}t valid is skipped, a layout that
    /// doesn\u{2019}t fit is fitted, and the widgets you made on this Mac that run a program stay (they are never in a file).
    /// Launch at Login is the system\u{2019}s, so it is not in the file.
    func restore(_ archive: SettingsArchive) {
        if let stored = archive.openShortcut { setShortcut(.open, stored.combo) }
        if let stored = archive.shelfShortcut { setShortcut(.shelf, stored.combo) }
        if let value = archive.peeksOnHover { peeksOnHover = value }
        if let value = archive.swipesEnabled { swipesEnabled = value }
        if let value = archive.islandDisplay.flatMap(IslandDisplay.init) { islandDisplay = value }

        if archive.leftTabs != nil || archive.rightTabs != nil {
            let modules = { (names: [String]?) in (names ?? []).compactMap(IslandModule.init) }
            replaceTabs(left: modules(archive.leftTabs), right: modules(archive.rightTabs))
        }
        if let names = archive.menuBarModules {
            let wanted = names.compactMap(IslandModule.init).filter(\.isAvailable)
            for module in IslandModule.allCases where module.isAvailable {
                setInMenuBar(module, wanted.contains(module))
            }
        }
        if let value = archive.showsCalendar { showsCalendar = value }
        if let value = archive.showsReminders { showsReminders = value }
        if let value = archive.showsTimeLeft, value != showsTimeLeft { showsTimeLeft = value }
        if let value = archive.countsDownToEveryEvent { countsDownToEveryEvent = value }
        // Both on first, so turning one off (below) is never refused for the other being off.
        if archive.readsClaudeCode != nil || archive.readsCodex != nil {
            setReads(.claudeCode, true)
            setReads(.codex, true)
            if archive.readsClaudeCode == false, archive.readsCodex != false { setReads(.claudeCode, false) }
            if archive.readsCodex == false, archive.readsClaudeCode != false { setReads(.codex, false) }
        }
        if let value = archive.showsAgentCompact { showsAgentCompact = value }
        if let value = archive.agentFinishMinimum, Self.agentMinimums.contains(value) { agentFinishMinimum = value }
        if let value = archive.agentLimitThreshold, Self.agentThresholds.contains(value) { agentLimitThreshold = value }
        if let value = archive.showsLimitsLeft { showsLimitsLeft = value }
        if let value = archive.weatherCity { weatherCity = value }
        if let value = archive.dragTarget.flatMap(DragTarget.init) { dragTarget = value }
        if let value = archive.addsScreenshots { addsScreenshots = value }
        if let value = archive.shelfRetention.flatMap(ShelfRetention.init) { shelfRetention = value }
        if let value = archive.clipboardLimit, ClipboardHistory.limits.contains(value) {
            // A file from before the Clipboard feature turned the history off with a limit of 0.
            if value == 0 { setOn(.clipboard, false) }
            clipboardLimit = value == 0 ? ClipboardHistory.limit : value
        }
        if let value = archive.shelfMode.flatMap(ShelfMode.init) { shelfMode = value }
        if let value = archive.showsLyrics { showsLyrics = value }
        if let value = archive.replacesVolumeHUD, value != replacesVolumeHUD { replacesVolumeHUD = value }
        if let value = archive.showsMusicCompact { showsMusicCompact = value }
        if let value = archive.pinLimit.flatMap(PinLimit.init) { pinLimit = value }
        // Before the row, which may name them.
        if let tools = archive.shortcutTools { replaceShortcutTools(tools) }
        if let names = archive.pinnedTools {
            var seen = Set<ToolID>()
            replacePinned(names.compactMap(ToolID.init).filter { seen.insert($0).inserted })
        }
        if let value = archive.quietDuringFocus { quietDuringFocus = value }
        if let value = archive.fullChargeLevel, Self.fullChargeRange.contains(value) { fullChargeLevel = value }
        if let value = archive.pomodoroFocus, PomodoroPlan.focusRange.contains(value) { pomodoroFocus = value }
        if let value = archive.pomodoroShortBreak, PomodoroPlan.shortBreakRange.contains(value) {
            pomodoroShortBreak = value
        }
        if let value = archive.pomodoroLongBreak, PomodoroPlan.longBreakRange.contains(value) {
            pomodoroLongBreak = value
        }
        if let value = archive.pomodoroSessions, PomodoroPlan.sessionsRange.contains(value) {
            pomodoroSessions = value
        }
        // After the settings the switches share (Calendar, the Volume HUD, the clipboard's 0), so a file's features win.
        if let choices = archive.features {
            for feature in Feature.allCases {
                if let on = choices[feature.rawValue] { setOn(feature, on) }
            }
        }
        if let names = archive.mutedEvents {
            let muted = Set(names.compactMap(AmbientEvent.init))
            for event in AmbientEvent.allCases { setMuted(event, muted.contains(event)) }
        }
        if let home = archive.home {
            let plan = home.importPlan()
            // Widgets made here that run a program are not in a file, so they stay; the rest are the file's.
            replaceCustomWidgets(customWidgets.filter(\.isCommand) + plan.widgets)
            setHomeLayout(plan.layout)
        }
        // Features this file turned off take their widgets off Home.
        syncHomeWidgets()
    }

    /// Every choice back to what a fresh install has, including Home and every widget you made.
    func resetAll() {
        let name = "MacIslandDefaults.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: name) else { return }
        defer { scratch.removePersistentDomain(forName: name) }
        let fresh = AppSettings(defaults: scratch)
        var archive = SettingsArchive.make(from: fresh)
        archive.home = HomeArchive(layout: .default)
        restore(archive)
        replaceCustomWidgets([])
        setHomeLayout(.default)
        for preset in savedHomePresets { deleteHomePreset(preset.id) }
        clearHomeHiddenByFeature()
    }
}

/// The panels and confirmations around export, import, and reset.
@MainActor
enum SettingsArchivePanels {
    static func export(_ settings: AppSettings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacIsland.macislandsettings.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Command widgets are not included."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsArchive.make(from: settings).data().write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Reads a file and, after confirming, returns it.
    static func importArchive() -> SettingsArchive? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let archive = try SettingsArchive.read(Data(contentsOf: url))
            let alert = NSAlert()
            alert.messageText = "Replace Your Settings?"
            alert.informativeText = "\(archive.summary())\n\nFrom \u{201C}\(url.lastPathComponent)\u{201D}."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn ? archive : nil
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    static func confirmReset() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings?"
        alert.informativeText =
            "Every choice goes back to what a new install has, including Home and the widgets you made. This can\u{2019}t be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }
}
