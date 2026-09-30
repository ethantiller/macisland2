import Foundation
import Testing

@testable import MacIsland

/// Layouts the person saves: they join the Presets menu, come back with their options, and can be removed (the built-in ones can't).
@MainActor
struct SavedPresetTests {
    private func makeSettings() -> (AppSettings, UserDefaults) {
        let name = "MacIslandSaved.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppSettings(defaults: defaults), defaults)
    }

    private func makeEditor() -> (HomeEditor, AppSettings, UndoManager) {
        let (settings, _) = makeSettings()
        let editor = HomeEditor(settings: settings)
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        return (editor, settings, undo)
    }

    private func placement(_ widget: BuiltInWidget, _ columns: Int, _ rows: Int = 1) -> WidgetPlacement {
        WidgetPlacement(widget: .builtIn(widget), size: GridSize(columns, rows))
    }

    @Test func saveKeepsTheWidgetsAndSizesOnHomeUnderAName() throws {
        let (settings, _) = makeSettings()
        settings.setHomeLayout(HomeLayout(widgets: [placement(.music, 6, 2), placement(.weather, 1)]))
        guard case .saved(let preset) = settings.saveHomePreset(named: "  Night Mode ") else {
            Issue.record("expected it to be saved")
            return
        }
        #expect(preset.name == "Night Mode", "the space around it is dropped")
        #expect(preset.layout.widgets.map(\.widget) == [.builtIn(.music), .builtIn(.weather)])
        #expect(preset.layout.widgets.map(\.size) == [GridSize(6, 2), GridSize(1, 1)])
        #expect(preset.layout.hidden.isEmpty)
        #expect(settings.savedHomePresets == [preset])
    }

    @Test func savedLayoutsSurviveARelaunchInOrder() {
        let (settings, defaults) = makeSettings()
        settings.saveHomePreset(named: "One")
        settings.setHomeLayout(HomeLayout.presets[3].layout)
        settings.saveHomePreset(named: "Two")
        let reloaded = AppSettings(defaults: defaults).savedHomePresets
        #expect(reloaded.map(\.name) == ["One", "Two"])
        #expect(reloaded[1].layout.widgets.count == 2)
    }

    @Test func aNameCanBeNeitherEmptyNorABuiltInPresets() {
        let (settings, _) = makeSettings()
        #expect(settings.saveHomePreset(named: "   ") == .empty)
        #expect(settings.saveHomePreset(named: "Everyday") == .reserved)
        #expect(settings.saveHomePreset(named: " dashboard ") == .reserved, "whatever the case")
        #expect(settings.savedHomePresets.isEmpty)
        #expect(SavedHomePreset.isBuiltIn("Minimal") && !SavedHomePreset.isBuiltIn("Mine"))
    }

    @Test func savingANameAgainReplacesThatLayout() {
        let (settings, _) = makeSettings()
        settings.saveHomePreset(named: "Mine")
        settings.setHomeLayout(HomeLayout.presets[3].layout)
        guard case .replaced(let replaced) = settings.saveHomePreset(named: "mine") else {
            Issue.record("expected a replacement")
            return
        }
        #expect(settings.savedHomePresets.count == 1 && settings.savedHomePresets[0].name == "Mine")
        #expect(replaced.layout.widgets.count == 2, "it holds the new arrangement")
    }

    @Test func theSuggestedNameSkipsTheOnesTaken() {
        #expect(SavedHomePreset.suggestedName(among: []) == "My Layout")
        let taken = [
            SavedHomePreset(name: "My Layout", layout: .default),
            SavedHomePreset(name: "my layout 2", layout: .default),
        ]
        #expect(SavedHomePreset.suggestedName(among: taken) == "My Layout 3")
    }

    @Test func aSavedLayoutComesBackWithItsOwnOptions() throws {
        let (editor, settings, undo) = makeEditor()
        // Shelf hidden on the Timers widget, then saved.
        editor.undoManager = nil
        var options = WidgetOptions()
        options.showsShelf = false
        let pill = settings.homeLayout.widgets[3]
        editor.setOptions(options, for: pill.id)
        editor.saveLayout(named: "No Shelf")
        let saved = try #require(settings.savedHomePresets.first)
        // The options change afterwards; applying the saved layout puts the saved ones back.
        editor.setOptions(WidgetOptions(), for: pill.id)
        #expect(settings.homeLayout.widgets[3].options.showsShelf == nil)
        editor.undoManager = undo
        undo.beginUndoGrouping()
        editor.applySaved(saved)
        undo.endUndoGrouping()
        #expect(settings.homeLayout.widgets[3].options.showsShelf == false)
        #expect(undo.undoActionName == "Use No Shelf")
    }

    @Test func aBuiltInPresetStillKeepsYourOptions() {
        let (editor, settings, _) = makeEditor()
        editor.undoManager = nil
        var options = WidgetOptions()
        options.showsShelf = false
        editor.setOptions(options, for: settings.homeLayout.widgets[3].id)
        editor.applyPreset(HomeLayout.presets[0])
        #expect(settings.homeLayout.widgets[3].options.showsShelf == false)
    }

    @Test func aSavedLayoutIsRemovedAndUndoPutsItBackWhereItWas() {
        let (editor, settings, undo) = makeEditor()
        editor.saveLayout(named: "A")
        editor.saveLayout(named: "B")
        editor.saveLayout(named: "C")
        let b = settings.savedHomePresets[1]
        undo.beginUndoGrouping()
        editor.deleteSaved(b.id)
        undo.endUndoGrouping()
        #expect(settings.savedHomePresets.map(\.name) == ["A", "C"])
        undo.undo()
        #expect(settings.savedHomePresets.map(\.name) == ["A", "B", "C"])
        undo.redo()
        #expect(settings.savedHomePresets.map(\.name) == ["A", "C"])
    }

    @Test func theBuiltInPresetsAreNeverInTheSavedList() {
        let (settings, _) = makeSettings()
        settings.saveHomePreset(named: "Mine")
        #expect(settings.savedHomePresets.count == 1)
        #expect(HomeLayout.presets.map(\.name) == ["Everyday", "Focus", "Listening", "Minimal", "Dashboard"])
        #expect(settings.deleteHomePreset(UUID()) == nil, "nothing else can be removed")
    }

    @Test func aLayoutIsTheCurrentOneWhenItHasTheSameWidgetsAtTheSameSizes() {
        let saved = HomeLayout(
            widgets: HomeLayout.default.widgets.map { WidgetPlacement(widget: $0.widget, size: $0.size) })
        #expect(HomeLayout.default.hasSameArrangement(as: saved))
        #expect(!HomeLayout.default.hasSameArrangement(as: HomeLayout.presets[3].layout))
        var resized = saved
        resized.widgets[1].size = GridSize(6, 1)
        #expect(!HomeLayout.default.hasSameArrangement(as: resized))
    }

    @Test func resetAllForgetsSavedLayouts() {
        let (settings, _) = makeSettings()
        settings.saveHomePreset(named: "Mine")
        settings.resetAll()
        #expect(settings.savedHomePresets.isEmpty)
    }

    @Test func widgetsOffHomeAreWhatAddWidgetsOffers() {
        var layout = HomeLayout.default
        let custom = CustomWidget(title: "F", systemImage: "folder", source: .folder(path: "/tmp"))
        let offered = layout.addable(customs: [custom])
        #expect(offered.contains(.builtIn(.weather)) && offered.contains(.custom(custom.id)))
        #expect(!offered.contains(.builtIn(.today)))
        // Taken off Home, a widget is offered again.
        layout = layout.removing(layout.widgets[1].id)
        #expect(layout.addable(customs: []).contains(.builtIn(.music)))
        #expect(layout.addable(customs: []).count == BuiltInWidget.allCases.count - 3)
    }
}

/// The gallery: what each size of a widget offers, and whether it would fit.
struct WidgetGalleryTests {
    private func placement(_ widget: BuiltInWidget, _ columns: Int, _ rows: Int = 1) -> WidgetPlacement {
        WidgetPlacement(widget: .builtIn(widget), size: GridSize(columns, rows))
    }

    @Test func noRoomIsDecidedForEachSizeSeparately() {
        // Music 6 by 2 and Timers 5 by 1 leave one free cell.
        let layout = HomeLayout(widgets: [placement(.music, 6, 2), placement(.clockActions, 5)])
        #expect(layout.fits(.builtIn(.weather), size: GridSize(1, 1)))
        #expect(!layout.fits(.builtIn(.weather), size: GridSize(2, 1)), "two cells won't go in one")
        #expect(!layout.fits(.builtIn(.weather), size: GridSize(3, 2)))
        #expect(!layout.fits(.builtIn(.weather), size: GridSize(7, 7)), "not a size it has")
    }

    @Test func aFullHomeHasNoRoomAtAnySize() {
        let full = HomeLayout(widgets: [placement(.music, 6, 2), placement(.quickTools, 6)])
        for size in WidgetCatalog.descriptor(builtIn: .battery).sizes {
            #expect(!full.fits(.builtIn(.battery), size: size), "\(size)")
        }
    }

    @Test func aWidgetOnHomeIsNotOfferedAndDoesntFitTwice() {
        let layout = HomeLayout.default
        #expect(!layout.fits(.builtIn(.today), size: GridSize(3, 1)))
        #expect(!layout.addable(customs: []).contains(.builtIn(.today)))
        #expect(layout.addable(customs: []).count == BuiltInWidget.allCases.count - 4)
    }

    @Test func aSizeThatFitsIsAddedAtThatSize() throws {
        let layout = HomeLayout.default
        #expect(layout.fits(.builtIn(.weather), size: GridSize(3, 1)))
        let added = try #require(layout.adding(.builtIn(.weather), size: GridSize(3, 1)))
        #expect(added.widgets.last?.size == GridSize(3, 1))
    }
}

/// Tools that were removed (Low Power, Lock Screen) must not take a widget off Home when they are still in a saved layout.
struct RemovedToolTests {
    private func decode(_ json: String) throws -> HomeLayout {
        try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
    }

    private func layout(tools: String) -> String {
        #"""
        {"version":2,"widgets":[{"id":"\#(UUID().uuidString)","widget":"quickTools","size":"2x1","options":{"tools":\#(tools)}},
        {"id":"\#(UUID().uuidString)","widget":"today","size":"3x1","options":{}}],"hidden":[]}
        """#
    }

    @Test func aRemovedToolIsDroppedAndTheWidgetStays() throws {
        let decoded = try decode(layout(tools: #"["keepAwake","lowPower","focus","lockScreen"]"#))
        #expect(decoded.widgets.map(\.widget) == [.builtIn(.quickTools), .builtIn(.today)])
        #expect(decoded.widgets[0].options.tools == [.keepAwake, .focus])
    }

    @Test func aChoiceMadeOnlyOfRemovedToolsFollowsTheToolsRowAgain() throws {
        let decoded = try decode(layout(tools: #"["lowPower","lockScreen"]"#))
        #expect(decoded.widgets[0].options.tools == nil)
    }

    @Test func currentToolsAndOtherOptionsStillRoundTrip() throws {
        var options = WidgetOptions()
        options.tools = [.mirror, .focus]
        options.timerMinutes = [10, 45]
        options.showsShelf = false
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(WidgetOptions.self, from: data) == options)
        #expect(try JSONDecoder().decode(WidgetOptions.self, from: Data("{}".utf8)) == WidgetOptions())
    }

    @Test func removedToolsAreNotTools() {
        #expect(ToolID(rawValue: "lowPower") == nil && ToolID(rawValue: "lockScreen") == nil)
        #expect(ToolID.allCases.count == 9)
    }
}
