import Foundation
import Testing

@testable import MacIsland

/// Version 1 of Home's layout (rows of widgets) becomes version 2 (an ordered list, each with a size) once, on read.
struct HomeMigrationTests {
    private func v1Placement(_ widget: String) -> String {
        #"{"id":"\#(UUID().uuidString)","widget":"\#(widget)","options":{}}"#
    }

    private func v1(_ rows: [[String]], hidden: [String] = []) -> String {
        let rows = rows.map { "[" + $0.map(v1Placement).joined(separator: ",") + "]" }.joined(separator: ",")
        return #"{"version":1,"rows":[\#(rows)],"hidden":[\#(hidden.map(v1Placement).joined(separator: ","))]}"#
    }

    private func migrated(_ rows: [[String]], hidden: [String] = []) throws -> HomeLayout {
        try JSONDecoder().decode(HomeLayout.self, from: Data(v1(rows, hidden: hidden).utf8))
    }

    /// "today 3x1": what a person would read off the layout.
    private func summary(_ layout: HomeLayout) -> [String] {
        layout.widgets.map { "\($0.widget.rawValue) \($0.size)" }
    }

    @Test func v1DefaultBecomesV2Default() throws {
        let layout = try migrated([["today", "music"], ["quickTools", "clockActions"]])
        #expect(summary(layout) == summary(.default))
        #expect(layout.version == 2 && layout.hidden.isEmpty)
        // Row 1 is exactly where it was; row 2 is the agreed 72 | 392.
        #expect(HomeLayout.normalized(layout).widgets.map(\.size) == HomeLayout.default.widgets.map(\.size))
        #expect(layout.contentHeight() == 138)
    }

    @Test func focusListeningAndMinimalKeepTheirShapes() throws {
        #expect(
            summary(try migrated([["today", "reminders"], ["quickTools", "clockActions"]]))
                == ["today 3x1", "reminders 3x1", "quickTools 1x1", "clockActions 5x1"])
        #expect(
            summary(try migrated([["music"], ["weather", "quickTools", "clockActions"]]))
                == ["music 6x1", "weather 1x1", "quickTools 1x1", "clockActions 4x1"])
        #expect(summary(try migrated([["today", "music"]])) == ["today 3x1", "music 3x1"])
    }

    @Test func aStripOfTimerChipsBecomesTimersAndShelf() throws {
        #expect(
            summary(try migrated([["today", "music"], ["timerChips"]]))
                == ["today 3x1", "music 3x1", "clockActions 6x1"])
        // With Timers & Shelf already on Home, the chips (which had no options) are dropped.
        #expect(
            summary(try migrated([["today", "music"], ["quickTools", "clockActions"], ["timerChips"]]))
                == summary(.default))
        // Off Home, they are simply gone.
        #expect(
            try migrated([["today"]], hidden: ["timerChips", "weather"]).hidden.map(\.widget) == [.builtIn(.weather)])
    }

    @Test func flexibleWidgetsShareARowAsEvenlyAsTheyCan() throws {
        #expect(
            summary(try migrated([["today", "music", "reminders"]]))
                == ["today 2x1", "music 2x1", "reminders 2x1"])
        #expect(summary(try migrated([["today", "note"], ["music"]])) == ["today 3x1", "note 3x1", "music 6x1"])
        // A widget takes the largest width it has that is no more than its share.
        #expect(summary(try migrated([["battery", "today"]])) == ["battery 1x1", "today 3x1"])
    }

    @Test func aCustomWidgetAloneIsThreeWide() throws {
        let id = UUID()
        let layout = try migrated([["custom:\(id.uuidString)"]])
        #expect(layout.widgets.map(\.widget) == [.custom(id)])
        #expect(layout.widgets.map(\.size) == [GridSize(3, 1)])
    }

    @Test func idsAndOptionsSurviveAndHiddenWidgetsComeBackAtTheirDefaultSize() throws {
        let id = UUID()
        let json = #"""
            {"version":1,"rows":[[{"id":"\#(id.uuidString)","widget":"clockActions","options":{"timerMinutes":[10,45]}}]],
            "hidden":[{"id":"\#(UUID().uuidString)","widget":"weather","options":{}},
            {"id":"\#(UUID().uuidString)","widget":"from-the-future","options":{}}]}
            """#
        let layout = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(layout.widgets.first?.id == id)
        #expect(layout.widgets.first?.options.timerMinutes == [10, 45])
        #expect(
            layout.hidden.map(\.widget) == [.builtIn(.weather)],
            "a widget this build doesn't know is dropped, as before")
        #expect(layout.hidden.first?.size == GridSize(1, 1))
    }

    @Test func aWidgetWithoutADescriptorIsKeptOffHomeAcrossARoundTrip() throws {
        let unknown = WidgetPlacement(widget: .custom(UUID()), size: GridSize(2, 1))
        let repaired = HomeLayout.normalized(HomeLayout(widgets: HomeLayout.default.widgets + [unknown]))
        #expect(repaired.hidden.map(\.widget) == [unknown.widget])
        let data = try JSONEncoder().encode(repaired)
        let again = HomeLayout.normalized(try JSONDecoder().decode(HomeLayout.self, from: data))
        #expect(again == repaired)
    }

    @Test func v2IsWhatIsWrittenAndReadBack() throws {
        let data = try JSONEncoder().encode(HomeLayout.default)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""widgets""#) && !text.contains(#""rows""#) && text.contains(#""version":2"#))
    }
}

@MainActor
struct HomeMigrationStorageTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MacIslandMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func placement(_ widget: String) -> String {
        #"{"id":"\#(UUID().uuidString)","widget":"\#(widget)","options":{}}"#
    }

    private var v1Focus: String {
        let rows = [["today", "reminders"], ["quickTools", "clockActions"]]
            .map { "[" + $0.map(placement).joined(separator: ",") + "]" }.joined(separator: ",")
        return #"{"version":1,"rows":[\#(rows)],"hidden":[]}"#
    }

    @Test func aStoredV1LayoutLoadsMigratedAndStaysV1UntilAnEdit() {
        let defaults = makeDefaults()
        let bytes = Data(v1Focus.utf8)
        defaults.set(bytes, forKey: "home.layout")
        let settings = AppSettings(defaults: defaults)
        #expect(
            settings.homeLayout.widgets.map(\.widget) == [
                .builtIn(.today), .builtIn(.reminders), .builtIn(.quickTools), .builtIn(.clockActions),
            ])
        #expect(
            settings.homeLayout.widgets.map(\.size) == [GridSize(3, 1), GridSize(3, 1), GridSize(1, 1), GridSize(5, 1)])
        #expect(defaults.data(forKey: "home.layout") == bytes, "reading never writes")

        settings.setHomeLayout(settings.homeLayout.removing(settings.homeLayout.widgets[1].id))
        let written = defaults.data(forKey: "home.layout").map { String(decoding: $0, as: UTF8.self) } ?? ""
        #expect(written.contains(#""widgets""#) && !written.contains(#""rows""#))
        #expect(AppSettings(defaults: defaults).homeLayout == settings.homeLayout)
    }

    @Test func aV1HomeFileImports() throws {
        let json = #"{"format":"MacIsland Home","version":1,"layout":\#(v1Focus)}"#
        let plan = try HomeArchive.read(Data(json.utf8)).importPlan()
        #expect(plan.layout.widgets.map(\.size) == [GridSize(3, 1), GridSize(3, 1), GridSize(1, 1), GridSize(5, 1)])
        #expect(plan.layout.widgets.first?.widget == .builtIn(.today))
    }

    @Test func aV1SettingsFileImports() throws {
        let json =
            #"{"format":"MacIsland Settings","version":1,"home":{"format":"MacIsland Home","version":1,"layout":\#(v1Focus)}}"#
        let archive = try SettingsArchive.read(Data(json.utf8))
        let settings = AppSettings(defaults: makeDefaults())
        settings.restore(archive)
        #expect(settings.homeLayout.widgets.map(\.widget).contains(.builtIn(.reminders)))
        #expect(
            settings.homeLayout.widgets.map(\.size) == [GridSize(3, 1), GridSize(3, 1), GridSize(1, 1), GridSize(5, 1)])
    }

    @Test func aFileFromANewerVersionIsStillRefused() throws {
        var home = HomeArchive(layout: .default)
        home.version = HomeArchive.currentVersion + 1
        #expect(throws: HomeArchive.ReadError.tooNew) { try HomeArchive.read(home.data()) }
        var settings = SettingsArchive()
        settings.version = SettingsArchive.currentVersion + 1
        #expect(throws: SettingsArchive.ReadError.tooNew) { try SettingsArchive.read(settings.data()) }
    }
}
