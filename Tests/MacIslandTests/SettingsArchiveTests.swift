import Carbon.HIToolbox
import Foundation
import Testing

@testable import MacIsland

@MainActor
struct SettingsArchiveTests {
    private func makeSettings() -> AppSettings {
        let name = "MacIslandArchive.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults)
    }

    /// A settings object with something changed in every section.
    private func customized() -> AppSettings {
        let settings = makeSettings()
        settings.setShortcut(
            .open, KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | optionKey), label: "J"))
        settings.setShortcut(.shelf, nil)
        settings.peeksOnHover = false
        settings.swipesEnabled = false
        settings.islandDisplay = .primary
        settings.move(.notes, to: .right)
        settings.setInMenuBar(.clock, true)
        settings.showsCalendar = true
        settings.showsReminders = true
        settings.weatherCity = "Paris"
        settings.dragTarget = .shelfOnly
        settings.addsScreenshots = false
        settings.shelfRetention = .week
        settings.clipboardLimit = 25
        settings.shelfMode = .clipboard
        settings.showsLyrics = false
        settings.showsMusicCompact = false
        settings.pinLimit = .eight
        settings.movePinned(settings.visiblePinned[4], before: settings.visiblePinned[0])
        settings.quietDuringFocus = true
        settings.fullChargeLevel = 90
        settings.pomodoroFocus = 50
        settings.pomodoroShortBreak = 10
        settings.pomodoroLongBreak = 30
        settings.pomodoroSessions = 6
        settings.setMuted(.hotspot, true)
        settings.setMuted(.lowDisk, true)
        settings.saveCustomWidget(
            CustomWidget(
                title: "Stocks", systemImage: "chart.line.uptrend.xyaxis",
                source: .web(url: URL(string: "https://api.example.com/q")!, path: "p")))
        var layout = settings.homeLayout
        layout.widgets[1] = WidgetPlacement(widget: .custom(settings.customWidgets[0].id), size: GridSize(2, 1))
        settings.setHomeLayout(layout)
        return settings
    }

    @Test func aRoundTripRestoresEveryChoice() throws {
        let original = customized()
        let data = try SettingsArchive.make(from: original).data()
        let target = makeSettings()
        target.restore(try SettingsArchive.read(data))

        #expect(target.openShortcut == original.openShortcut)
        #expect(target.shelfShortcut == nil)
        #expect(!target.peeksOnHover && !target.swipesEnabled && target.islandDisplay == .primary)
        #expect(target.leftTabs == original.leftTabs && target.rightTabs == original.rightTabs)
        #expect(target.menuBarModules == original.menuBarModules)
        #expect(target.showsCalendar && target.showsReminders && target.weatherCity == "Paris")
        #expect(target.dragTarget == .shelfOnly && !target.addsScreenshots && target.shelfRetention == .week)
        #expect(target.clipboardLimit == 25 && target.shelfMode == .clipboard)
        #expect(!target.showsLyrics && !target.showsMusicCompact)
        #expect(target.pinLimit == .eight && target.visiblePinned == original.visiblePinned)
        #expect(target.quietDuringFocus && target.fullChargeLevel == 90)
        #expect(target.pomodoroPlan == PomodoroPlan(focus: 50, shortBreak: 10, longBreak: 30, sessions: 6))
        #expect(target.mutedEvents == [.hotspot, .lowDisk])
        #expect(target.customWidgets.map(\.title) == ["Stocks"])
        #expect(target.homeLayout.widgets[1].widget == .custom(target.customWidgets[0].id))
    }

    @Test func aFileOfTheWrongKindOrTooNewIsRefused() throws {
        #expect(throws: SettingsArchive.ReadError.notAnArchive) { try SettingsArchive.read(Data("{}".utf8)) }
        #expect(throws: SettingsArchive.ReadError.notAnArchive) {
            try SettingsArchive.read(HomeArchive(layout: .default).data())
        }
        var newer = SettingsArchive()
        newer.version = 42
        #expect(throws: SettingsArchive.ReadError.tooNew) { try SettingsArchive.read(newer.data()) }
    }

    @Test func aFileWithFewerFieldsLeavesTheRestAlone() throws {
        let settings = customized()
        let sparse = Data(#"{"format":"MacIsland Settings","version":1,"peeksOnHover":true}"#.utf8)
        settings.restore(try SettingsArchive.read(sparse))
        #expect(settings.peeksOnHover)
        #expect(settings.weatherCity == "Paris" && settings.clipboardLimit == 25)
    }

    @Test func invalidValuesAreSkippedAndListsAreRepaired() throws {
        let settings = makeSettings()
        var archive = SettingsArchive()
        archive.clipboardLimit = 7
        archive.fullChargeLevel = 12
        archive.pomodoroFocus = 500
        archive.pomodoroSessions = 1
        archive.islandDisplay = "moon"
        archive.dragTarget = "explode"
        archive.pinLimit = 5
        archive.leftTabs = ["home", "home", "bogus", "media"]
        archive.pinnedTools = ["keepAwake", "keepAwake", "nope", "ringLight"]
        archive.openShortcut = StoredShortcut(
            combo: KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: 0, label: "J"))
        settings.restore(archive)
        #expect(settings.clipboardLimit == 10 && settings.fullChargeLevel == 100)
        #expect(settings.pomodoroPlan == PomodoroPlan.default, "out-of-range lengths are skipped")
        #expect(settings.islandDisplay == .builtIn && settings.dragTarget == .shelfAndAirDrop)
        #expect(settings.pinLimit == .six)
        #expect(settings.leftTabs == [.home, .media])
        #expect(settings.pinnedTools == [.keepAwake, .ringLight])
        #expect(settings.openShortcut == .openDefault, "a shortcut without a modifier is refused")
    }

    @Test func commandWidgetsAreNeverWrittenOrRead() throws {
        let settings = customized()
        let command = CustomWidget(title: "Run", systemImage: "terminal", source: .command(path: "/tmp/run.sh"))
        settings.saveCustomWidget(command)
        var layout = settings.homeLayout
        layout.hidden.append(WidgetPlacement(widget: .custom(command.id)))
        settings.setHomeLayout(layout)

        let text = String(decoding: try SettingsArchive.make(from: settings).data(), as: UTF8.self)
        #expect(!text.contains("/tmp/run.sh") && !text.contains("command"))

        // A file someone wrote by hand with a command in it.
        var hostile = SettingsArchive.make(from: makeSettings())
        hostile.home = HomeArchive(layout: .default, widgets: [command])
        let target = makeSettings()
        target.restore(hostile)
        #expect(target.customWidgets.isEmpty)
    }

    @Test func aCommandYouMadeHereSurvivesAnImport() throws {
        let target = makeSettings()
        let command = CustomWidget(title: "Run", systemImage: "terminal", source: .command(path: "/tmp/run.sh"))
        target.saveCustomWidget(command)
        target.restore(try SettingsArchive.read(SettingsArchive.make(from: customized()).data()))
        #expect(target.customWidgets.contains { $0.isCommand })
        #expect(target.customWidgets.contains { $0.title == "Stocks" })
    }

    @Test func importedWidgetsGetNewIDs() throws {
        let original = customized()
        let target = makeSettings()
        target.restore(try SettingsArchive.read(SettingsArchive.make(from: original).data()))
        #expect(target.customWidgets[0].id != original.customWidgets[0].id)
    }

    @Test func resetAllGoesBackToAFreshInstall() {
        let settings = customized()
        settings.saveCustomWidget(CustomWidget(title: "Run", systemImage: "terminal", source: .command(path: "/tmp/x")))
        settings.resetAll()
        let fresh = makeSettings()
        #expect(settings.homeLayout == .default && settings.customWidgets.isEmpty)
        #expect(settings.openShortcut == .openDefault)
        #expect(settings.peeksOnHover && settings.swipesEnabled && settings.islandDisplay == .builtIn)
        #expect(settings.tabs == fresh.tabs && settings.menuBarModules.isEmpty)
        #expect(!settings.showsCalendar && settings.weatherCity.isEmpty)
        #expect(
            settings.dragTarget == .shelfAndAirDrop && settings.addsScreenshots && settings.shelfRetention == .never)
        #expect(settings.clipboardLimit == 10 && settings.shelfMode == .files && settings.showsMusicCompact)
        #expect(settings.pinLimit == .six && settings.visiblePinned == fresh.visiblePinned)
        #expect(settings.mutedEvents.isEmpty)
        #expect(settings.showsLyrics && !settings.quietDuringFocus && settings.fullChargeLevel == 100)
    }
}
