import Foundation
import Testing

@testable import MacIsland

private func placement(_ widget: BuiltInWidget, _ columns: Int = 0, _ rows: Int = 1) -> WidgetPlacement {
    WidgetPlacement(
        widget: .builtIn(widget), size: columns == 0 ? .unset : GridSize(columns, rows))
}

private func custom(_ id: UUID, _ columns: Int = 2) -> WidgetPlacement {
    WidgetPlacement(widget: .custom(id), size: GridSize(columns, 1))
}

private func ids(_ layout: HomeLayout) -> [WidgetID] { layout.widgets.map(\.widget) }

/// Three rows and no free cell.
private let fullLayout = HomeLayout(widgets: [placement(.music, 6, 2), placement(.quickTools, 6, 1)])

struct HomeLayoutTests {
    private let catalog = WidgetCatalog.descriptor(for:)

    @Test func theDefaultIsTodaysHome() {
        let layout = HomeLayout.default
        #expect(ids(layout) == [.builtIn(.today), .builtIn(.music), .builtIn(.quickTools), .builtIn(.clockActions)])
        #expect(layout.widgets.map(\.size) == [GridSize(3, 1), GridSize(3, 1), GridSize(1, 1), GridSize(5, 1)])
        // Row 1: two halves. Row 2: the 72 pt tools grid, and the pill takes the rest.
        let frames = layout.widgets.compactMap { layout.frames()[$0.id].map(HomeGridSpec.frame(of:)) }
        #expect(frames.map(\.width) == [232, 232, 72, 392])
        #expect(frames.map(\.height) == [64, 64, 64, 64])
        #expect(frames.map(\.minY) == [0, 0, 74, 74])
        #expect(layout.rowsUsed() == 2)
        #expect(layout.contentHeight() == 138)
        #expect(layout.contentHeight() == Theme.Metrics.homeContentHeight)
        #expect(layout.hidden.isEmpty)
    }

    @Test func theBudgetIsTheWorstCasePanel() {
        #expect(Theme.Metrics.homeContentWidth == 472)
        #expect(Theme.Metrics.homeContentWidth == Theme.Metrics.detachedWidth)
        #expect(Theme.Metrics.homeMaxContentHeight == 212)
        #expect(Theme.Metrics.panelHeight == 276)
        #expect(ScreenGeometry.panelSize == CGSize(width: 560, height: 276))
    }

    @Test func everyPresetIsItsOwnNormalizedFormAndFits() {
        for preset in HomeLayout.presets {
            #expect(HomeLayout.normalized(preset.layout) == preset.layout, "\(preset.name)")
            #expect(preset.layout.contentHeight() <= Theme.Metrics.homeMaxContentHeight, "\(preset.name)")
            #expect(preset.layout.isValid(), "\(preset.name)")
        }
        #expect(HomeLayout.presets.first?.layout == .default)
    }

    @Test func aMissingOrUnsupportedSizeBecomesTheNearestOne() {
        let layout = HomeLayout(widgets: [
            placement(.weather),  // no size: its default
            placement(.today, 4, 1),  // no 4 wide: the nearest width on the same height
            placement(.battery, 1, 2),  // the same width, the nearest height
            placement(.note, 5, 3),  // nothing alike: its default
        ])
        let sizes = HomeLayout.normalized(layout).widgets.map(\.size)
        #expect(sizes == [GridSize(1, 1), GridSize(3, 1), GridSize(1, 1), GridSize(3, 1)])
    }

    @Test func aHomeTallerThanThreeRowsGoesToTheWidgetsThatDontFit() {
        // Three rows are 212.
        let three = HomeLayout(widgets: [
            placement(.today, 3), placement(.music, 3), placement(.quickTools, 1), placement(.clockActions, 5),
            placement(.reminders, 3), placement(.note, 3),
        ])
        #expect(three.contentHeight() == 212)
        #expect(HomeLayout.normalized(three) == three)

        // Every cell is taken, so the next widget has no room.
        var full = three
        full.widgets.append(placement(.battery, 1))
        full.widgets.append(placement(.weather, 1))
        let repaired = HomeLayout.normalized(full)
        #expect(repaired.rowsUsed() == 3)
        #expect(repaired.widgets.count == 6)
        #expect(ids(repaired) == ids(three))
        #expect(Set(repaired.hidden.map(\.widget)) == [.builtIn(.battery), .builtIn(.weather)])
    }

    @Test func whatDoesntFitGoesToHiddenAndNothingIsDeleted() {
        let unknown = WidgetPlacement(widget: .custom(UUID()))
        let layout = HomeLayout(widgets: [
            placement(.today, 3), placement(.today, 3), unknown, placement(.weather, 1), placement(.music, 3),
            placement(.note, 6, 2),
        ])
        let repaired = HomeLayout.normalized(layout)
        // The repeat, the widget this build has no descriptor for, and the one too tall for what is left.
        #expect(ids(repaired) == [.builtIn(.today), .builtIn(.weather), .builtIn(.music)])
        #expect(Set(repaired.hidden.map(\.widget)) == [.builtIn(.today), unknown.widget, .builtIn(.note)])
    }

    @Test func aWidgetIsNeverBothShownAndHidden() {
        var layout = HomeLayout.default
        layout.hidden = [placement(.today, 3), placement(.weather, 1)]
        let repaired = HomeLayout.normalized(layout)
        #expect(repaired.hidden.map(\.widget) == [.builtIn(.weather)])
    }

    @Test func anEmptyLayoutFallsBackToTheDefault() {
        #expect(HomeLayout.normalized(HomeLayout(widgets: [])).widgets == HomeLayout.default.widgets)
        let unknown = WidgetPlacement(widget: .custom(UUID()))
        let repaired = HomeLayout.normalized(HomeLayout(widgets: [unknown], hidden: [placement(.weather, 1)]))
        #expect(repaired.widgets == HomeLayout.default.widgets)
        #expect(Set(repaired.hidden.map(\.widget)) == [unknown.widget, .builtIn(.weather)])
    }

    @Test func aLayoutIsValidWhenEverythingIsOnTheGridAtASizeItHas() {
        #expect(HomeLayout.default.isValid())
        #expect(fullLayout.isValid())
        #expect(!HomeLayout(widgets: []).isValid())
        #expect(!HomeLayout(widgets: [placement(.today, 4, 1)]).isValid(), "no such size")
        #expect(!HomeLayout(widgets: [placement(.today)]).isValid(), "no size yet")
        var overflowing = fullLayout
        overflowing.widgets.append(placement(.battery, 1))
        #expect(!overflowing.isValid(), "no room left")
    }

    @Test func encodesAndDecodesAndDropsWidgetsItDoesntKnow() throws {
        let data = try JSONEncoder().encode(HomeLayout.default)
        #expect(try JSONDecoder().decode(HomeLayout.self, from: data) == .default)
        #expect(String(decoding: data, as: UTF8.self).contains(#""size":"3x1""#))

        let json = #"""
            {"version":2,"widgets":[{"id":"\#(UUID().uuidString)","widget":"today","size":"3x1","options":{}},
            {"id":"\#(UUID().uuidString)","widget":"from-the-future","size":"3x1","options":{}},
            {"id":"\#(UUID().uuidString)","widget":"music","options":{}}],"hidden":[]}
            """#
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(ids(decoded) == [.builtIn(.today), .builtIn(.music)])
        #expect(decoded.widgets.map(\.size) == [GridSize(3, 1), .unset], "a missing size is left to normalized")
    }

    @Test func widgetIDsReadAsPlainStrings() throws {
        let id = UUID()
        for widget in [WidgetID.builtIn(.weather), .custom(id)] {
            let data = try JSONEncoder().encode([widget])
            #expect(try JSONDecoder().decode([WidgetID].self, from: data) == [widget])
        }
        #expect(WidgetID.custom(id).rawValue == "custom:\(id.uuidString)")
        #expect(WidgetID(rawValue: "nope") == nil)
        #expect(WidgetID(rawValue: "timerChips") == nil, "retired: Timers & Shelf")
    }

    @Test func everyBuiltInHasADescriptorWithSizesThatFitTheGrid() {
        for widget in BuiltInWidget.allCases {
            let descriptor = WidgetCatalog.descriptor(builtIn: widget)
            #expect(descriptor.id == .builtIn(widget))
            #expect(descriptor.sizes.contains(descriptor.defaultSize), "\(widget)")
            #expect(Set(descriptor.sizes).count == descriptor.sizes.count, "\(widget)")
            #expect(
                descriptor.sizes.allSatisfy {
                    (1...Theme.Metrics.homeColumns).contains($0.columns)
                        && (1...Theme.Metrics.homeMaxRows).contains($0.rows)
                }, "\(widget)")
        }
        #expect(BuiltInWidget.allCases.count == 11)
    }

    @Test func aCustomWidgetHasSizesByItsKind() {
        let value = CustomWidget(title: "A", systemImage: "star", source: .folder(path: "/tmp"))
        let button = CustomWidget(title: "B", systemImage: "star", source: .shortcut(name: "X", showsResult: false))
        #expect(value.descriptor.sizes == [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1)])
        #expect(button.descriptor.sizes == [GridSize(1, 1), GridSize(2, 1)])
        #expect(value.descriptor.sizes.contains(value.descriptor.defaultSize))
    }
}

@MainActor
struct HomeSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MacIslandWidgets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func homeIsTheDefaultUntilEdited() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.homeLayout == .default)
        #expect(settings.homeContentHeight == Theme.Metrics.homeContentHeight)
        #expect(defaults.data(forKey: "home.layout") == nil)
    }

    @Test func aLayoutPersistsAcrossRelaunch() {
        let defaults = makeDefaults()
        let layout = HomeLayout(widgets: [
            placement(.today, 3), placement(.music, 3), placement(.weather, 1), placement(.quickTools, 1),
            placement(.clockActions, 4),
        ])
        AppSettings(defaults: defaults).setHomeLayout(layout)
        let loaded = AppSettings(defaults: defaults).homeLayout
        #expect(ids(loaded) == ids(layout))
        #expect(loaded.widgets.map(\.size) == layout.widgets.map(\.size))
    }

    @Test func settingALayoutRepairsItAndDoesNothingWhenUnchanged() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.setHomeLayout(.default)
        #expect(defaults.data(forKey: "home.layout") == nil, "no change, no write")

        let unknown = WidgetPlacement(widget: .custom(UUID()))
        settings.setHomeLayout(HomeLayout(widgets: [unknown]))
        #expect(settings.homeLayout.widgets == HomeLayout.default.widgets, "an empty result falls back")
        #expect(settings.homeLayout.hidden.map(\.widget) == [unknown.widget])
    }

    @Test func aLayoutThatWontDecodeShowsTheDefaultAndKeepsItsBytes() {
        let defaults = makeDefaults()
        let junk = Data("not json".utf8)
        defaults.set(junk, forKey: "home.layout")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.homeLayout == .default)
        #expect(defaults.data(forKey: "home.layout") == junk)
    }

    @Test func homeHeightFollowsTheLayout() {
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.contentHeight(for: .home) == 138)
        viewModel.settings.setHomeLayout(HomeLayout.presets[3].layout)  // Minimal: one row
        #expect(viewModel.contentHeight(for: .home) == 64)
        viewModel.settings.setHomeLayout(fullLayout)
        #expect(viewModel.contentHeight(for: .home) == 212)
        viewModel.settings.setHomeLayout(.default)
    }

    @Test func theTimersAndShelfPillFollowItsOptions() {
        let plain = HomeAction.list(timerActive: false, pomodoroActive: false, stopwatchActive: false, shelfCount: 0)
        #expect(plain.map(\.id) == ["timer5", "timer25", "pomodoro", "shelf"])
        let custom = HomeAction.list(
            timerActive: false, pomodoroActive: false, stopwatchActive: false, shelfCount: 0,
            timerMinutes: [10, 45], showsPomodoro: false, showsShelf: false)
        #expect(custom.map(\.id) == ["timer10", "timer45"])
        // A running Pomodoro shows even when its button is hidden.
        let running = HomeAction.list(
            timerActive: false, pomodoroActive: true, stopwatchActive: false, shelfCount: 0, showsPomodoro: false)
        #expect(running.contains(.runningPomodoro))
    }

    @Test func weatherFollowsTheSystemTemperatureUnit() {
        #expect(WeatherModel.usesFahrenheit(preference: "Fahrenheit", region: .metric))
        #expect(!WeatherModel.usesFahrenheit(preference: "Celsius", region: .us))
        #expect(WeatherModel.usesFahrenheit(preference: nil, region: .us))
        #expect(!WeatherModel.usesFahrenheit(preference: nil, region: .metric))
    }

    @Test func aNoteWidgetShowsTheLatestNoteOrTheOneChosen() {
        let viewModel = TestSupport.makeViewModel()
        let first = viewModel.notes.addNote()
        viewModel.notes.setBody("First\nSecond line\nThird", ofNote: first.id)
        #expect(NoteWidget.excerpt(of: viewModel.notes.notes[0]) == "Second line Third")
    }
}

struct HomeLayoutEditingTests {
    private let layout = HomeLayout.default

    @Test func aWidgetMovesBesideAnotherAndHomeGrowsARow() throws {
        let tools = layout.widgets[2]
        let moved = try #require(layout.placing(tools, at: .after(layout.widgets[0].id)))
        // Today, Quick Tools, Music, Timers: Music no longer fits beside them, so Home is three rows.
        #expect(ids(moved) == [.builtIn(.today), .builtIn(.quickTools), .builtIn(.music), .builtIn(.clockActions)])
        #expect(moved.rowsUsed() == 3)
        #expect(moved.isValid())
    }

    @Test func aWidgetDroppedOnACellGoesAfterTheOnesThatStartBeforeIt() throws {
        let music = layout.widgets[1]
        let first = try #require(layout.moving(music.id, toCell: GridCell(column: 0, row: 0)))
        #expect(ids(first) == [.builtIn(.music), .builtIn(.today), .builtIn(.quickTools), .builtIn(.clockActions)])
        #expect(first.rowsUsed() == 2)
        let back = try #require(first.moving(music.id, toCell: GridCell(column: 3, row: 0)))
        #expect(ids(back) == ids(layout))
    }

    @Test func aRefusedMoveChangesNothing() throws {
        // A widget that would leave the grid too tall is refused.
        let tall = WidgetPlacement(widget: .builtIn(.reminders), size: GridSize(6, 2))
        #expect(layout.placing(tall, at: .after(layout.widgets[3].id)) == nil)
        // A widget this build has no descriptor for can't be placed.
        #expect(layout.placing(WidgetPlacement(widget: .custom(UUID())), at: .after(layout.widgets[3].id)) == nil)
        // A target that isn't there.
        #expect(layout.placing(placement(.weather, 1), at: .after(UUID())) == nil)
        // Dropping on itself is a no-op.
        let today = layout.widgets[0]
        #expect(layout.placing(today, at: .before(today.id)) == layout)
    }

    @Test func aWidgetAppearsOnce() {
        let another = placement(.today, 3)
        #expect(layout.placing(another, at: .after(layout.widgets[2].id)) == nil)
        #expect(layout.adding(.builtIn(.today)) == nil)
    }

    @Test func removingKeepsOptionsAndSizeOffHomeAndNeverEmptiesHome() throws {
        var layout = layout
        var options = WidgetOptions()
        options.timerMinutes = [10, 45]
        let pill = layout.widgets[3]
        layout = layout.setting(options, for: pill.id)
        let removed = layout.removing(pill.id)
        #expect(removed.hidden.first?.options.timerMinutes == [10, 45])
        #expect(removed.index(of: pill.id) == nil)
        // Adding it back restores its options and its size.
        let added = try #require(removed.adding(.builtIn(.clockActions)))
        let back = try #require(added.widgets.first { $0.widget == .builtIn(.clockActions) })
        #expect(back.options.timerMinutes == [10, 45] && back.size == GridSize(5, 1))
        #expect(added.hidden.isEmpty)

        let single = HomeLayout(widgets: [placement(.today, 3)])
        #expect(single.removing(single.widgets[0].id) == single)
    }

    @Test func addingGoesWhereItFits() throws {
        let minimal = HomeLayout.presets[3].layout  // Today | Music, a full row
        let withWeather = try #require(minimal.adding(.builtIn(.weather)))
        #expect(ids(withWeather).last == .builtIn(.weather))
        #expect(withWeather.frames()[withWeather.widgets[2].id]?.origin == GridCell(column: 0, row: 1))
        #expect(withWeather.widgets[2].size == GridSize(1, 1))
        // A size can be asked for.
        let wide = try #require(minimal.adding(.builtIn(.weather), size: GridSize(6, 1)))
        #expect(wide.widgets[2].size == GridSize(6, 1))
    }

    @Test func addingFillsTheEarliestGapWhenNothingElseMoves() throws {
        // Today 3, Music 2, then Timers on its own row: one free cell is left at the end of row 1.
        let gappy = HomeLayout(widgets: [placement(.today, 3), placement(.music, 2), placement(.clockActions, 6)])
        let added = try #require(gappy.adding(.builtIn(.weather)))
        #expect(ids(added) == [.builtIn(.today), .builtIn(.music), .builtIn(.weather), .builtIn(.clockActions)])
        #expect(added.frames()[added.widgets[2].id]?.origin == GridCell(column: 5, row: 0))
        #expect(added.frames()[added.widgets[3].id]?.origin == GridCell(column: 0, row: 1), "Timers didn't move")
    }

    @Test func addingToAFullHomeHasNoRoom() {
        #expect(fullLayout.adding(.builtIn(.battery)) == nil)
        #expect(fullLayout.adding(.custom(UUID())) == nil, "and no descriptor")
    }

    @Test func movesGoLeftRightUpAndDown() throws {
        let today = layout.widgets[0]
        let music = layout.widgets[1]
        let tools = layout.widgets[2]
        #expect(layout.moving(today.id, .left) == nil)
        let swapped = try #require(layout.moving(today.id, .right))
        #expect(ids(swapped).prefix(2) == [.builtIn(.music), .builtIn(.today)])
        #expect(layout.moving(music.id, .up) == nil, "it is already in the top row")
        let down = try #require(layout.moving(today.id, .down))
        #expect(ids(down) == [.builtIn(.music), .builtIn(.quickTools), .builtIn(.today), .builtIn(.clockActions)])
        let up = try #require(layout.moving(tools.id, .up))
        #expect(ids(up).first == .builtIn(.quickTools))
        #expect(layout.moving(UUID(), .left) == nil)
    }

    @Test func aWidgetTakesOnlyTheSizesItHas() throws {
        let music = layout.widgets[1]
        let player = try #require(layout.resizing(music.id, to: GridSize(3, 2)))
        #expect(player.widgets[1].size == GridSize(3, 2))
        #expect(player.rowsUsed() == 3, "Timers no longer fits beside Quick Tools under a tall Music")
        #expect(layout.resizing(music.id, to: GridSize(4, 1)) == nil, "Music has no 4 by 1")
        let tools = layout.widgets[2]
        #expect(layout.resizing(tools.id, to: GridSize(6, 2)) == nil, "there would be no room for Timers")
        #expect(layout.resizing(UUID(), to: GridSize(3, 1)) == nil)
    }

    @Test func aPresetKeepsOptionsAndParksWhatItDoesntUse() {
        var layout = layout
        var options = WidgetOptions()
        options.showsShelf = false
        layout = layout.setting(options, for: layout.widgets[3].id)
        let minimal = layout.applying(HomeLayout.presets[3].layout)
        #expect(ids(minimal) == [.builtIn(.today), .builtIn(.music)])
        #expect(Set(minimal.hidden.map(\.widget)) == [.builtIn(.quickTools), .builtIn(.clockActions)])
        let back = minimal.applying(.default)
        #expect(back.widgets[3].options.showsShelf == false)
        #expect(back.hidden.isEmpty)
    }

    @Test func capacityIsSaidInWords() {
        #expect(layout.capacityText() == "Room for 1 more row")
        #expect(HomeLayout.presets[3].layout.capacityText() == "Room for 2 more rows")
        var threeRows = HomeLayout(widgets: layout.widgets + [placement(.reminders, 3), placement(.note, 2)])
        #expect(threeRows.capacityText() == "1 space left")
        threeRows.widgets.append(placement(.weather, 1))
        #expect(threeRows.capacityText() == "Home is full")
        #expect(fullLayout.capacityText() == "Home is full")
    }
}

@MainActor
struct HomeEditorTests {
    private func makeEditor() -> (editor: HomeEditor, settings: AppSettings, undo: UndoManager) {
        let name = "MacIslandEditor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        let editor = HomeEditor(settings: settings)
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        return (editor, settings, undo)
    }

    private func edit(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func removingAndAddingBackKeepsOptionsAndSize() {
        let (editor, settings, undo) = makeEditor()
        let pill = settings.homeLayout.widgets[3]
        var options = WidgetOptions()
        options.timerMinutes = [10, 45]
        edit(undo) { editor.setOptions(options, for: pill.id) }
        edit(undo) { editor.remove(pill.id) }
        #expect(settings.homeLayout.hidden.map(\.widget) == [.builtIn(.clockActions)])
        edit(undo) { editor.add(.builtIn(.clockActions)) }
        let back = settings.homeLayout.widgets.first { $0.widget == .builtIn(.clockActions) }
        #expect(back?.options.timerMinutes == [10, 45] && back?.size == GridSize(5, 1))
    }

    @Test func aRemovalSaysWhatHappenedAndUndoTakesItBack() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        edit(undo) { editor.remove(original.widgets[1].id) }
        #expect(editor.notice == "Removed Music.")
        undo.undo()
        #expect(settings.homeLayout == original)
    }

    @Test func movesAreOneUndoableStepEach() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        edit(undo) { editor.move(original.widgets[0].id, .right) }
        #expect(ids(settings.homeLayout).first == .builtIn(.music))
        undo.undo()
        #expect(settings.homeLayout == original)
        editor.move(original.widgets[0].id, .left)
        #expect(editor.refusal != nil, "it is already first")
    }

    @Test func aSizeIsOneUndoableStepAndAStepMovesToTheNextOne() {
        let (editor, settings, undo) = makeEditor()
        let today = settings.homeLayout.widgets[0]
        edit(undo) { editor.stepSize(today.id, by: 1) }
        #expect(settings.homeLayout.widgets[0].size == GridSize(3, 2))
        edit(undo) { editor.stepSize(today.id, by: -1) }
        #expect(settings.homeLayout.widgets[0].size == GridSize(3, 1))
        edit(undo) { editor.stepSize(today.id, by: -1) }
        #expect(settings.homeLayout.widgets[0].size == GridSize(2, 1))
        editor.stepSize(today.id, by: -1)
        #expect(editor.refusal?.contains("smallest") == true)
    }

    @Test func aPresetIsOneUndoableStepAndResetGoesBackToEveryday() {
        let (editor, settings, undo) = makeEditor()
        edit(undo) { editor.applyPreset(HomeLayout.presets[3]) }
        #expect(settings.homeLayout.widgets.count == 2)
        edit(undo) { editor.reset() }
        #expect(ids(settings.homeLayout) == ids(.default))
    }

    @Test func theLastWidgetCantBeRemoved() {
        let (editor, settings, _) = makeEditor()
        settings.setHomeLayout(HomeLayout(widgets: [placement(.today, 3)]))
        editor.remove(settings.homeLayout.widgets[0].id)
        #expect(settings.homeLayout.widgets.count == 1)
        #expect(editor.refusal != nil)
    }

    @Test func keysRemoveSelectMoveAndResize() {
        let (editor, settings, _) = makeEditor()
        editor.undoManager = nil
        #expect(!editor.perform(.delete), "nothing is selected")
        #expect(editor.perform(.select(.right)), "with nothing selected, the first widget")
        #expect(editor.selection == settings.homeLayout.widgets[0].id)
        let today = settings.homeLayout.widgets[0].id
        editor.perform(.select(.right))
        #expect(editor.selection == settings.homeLayout.widgets[1].id)
        editor.perform(.select(.down))
        #expect(editor.selection == settings.homeLayout.widgets[3].id, "Timers spans the column under Music")
        editor.perform(.select(.up))
        #expect(editor.selection == settings.homeLayout.widgets[0].id, "and Today is above Timers' first column")

        editor.selection = today
        #expect(editor.perform(.move(.right)))
        #expect(ids(settings.homeLayout).prefix(2) == [.builtIn(.music), .builtIn(.today)])
        #expect(editor.perform(.nextSize))
        #expect(settings.homeLayout.widgets.first { $0.id == today }?.size == GridSize(3, 2))
        #expect(editor.perform(.previousSize))
        #expect(editor.perform(.delete))
        #expect(settings.homeLayout.hidden.map(\.widget) == [.builtIn(.today)])
        #expect(editor.selection == nil)
        #expect(!editor.perform(.escape), "no drag to call off")
    }
}

struct HomeArchiveTests {
    @Test func aLayoutRoundTripsThroughAFile() throws {
        let data = try HomeArchive(layout: HomeLayout.presets[2].layout).data()
        let read = try HomeArchive.read(data)
        #expect(read.layout == HomeLayout.presets[2].layout)
        #expect(read.format == "MacIsland Home" && read.version == 2)
    }

    @Test func aFileOfTheWrongKindOrTooNewIsRefused() throws {
        #expect(throws: HomeArchive.ReadError.notAnArchive) { try HomeArchive.read(Data("{}".utf8)) }
        var wrongFormat = HomeArchive(layout: .default)
        wrongFormat.format = "Something Else"
        #expect(throws: HomeArchive.ReadError.notAnArchive) { try HomeArchive.read(wrongFormat.data()) }
        var newer = HomeArchive(layout: .default)
        newer.version = 99
        #expect(throws: HomeArchive.ReadError.tooNew) { try HomeArchive.read(newer.data()) }
    }

    @Test func aLayoutThatDoesntFitIsRepairedOnImport() throws {
        let broken = HomeLayout(widgets: fullLayout.widgets + [placement(.battery, 1)])
        let plan = try HomeArchive.read(HomeArchive(layout: broken).data()).importPlan()
        #expect(ids(plan.layout) == [.builtIn(.music), .builtIn(.quickTools)])
        #expect(plan.layout.hidden.map(\.widget) == [.builtIn(.battery)])
        #expect(plan.summary == "This uses only the built-in widgets.")
    }

    private func customs() -> (web: CustomWidget, command: CustomWidget, folder: CustomWidget) {
        (
            CustomWidget(
                title: "Stocks", systemImage: "chart.line.uptrend.xyaxis",
                source: .web(url: URL(string: "https://api.example.com/q")!, path: "p")),
            CustomWidget(title: "Run", systemImage: "terminal", source: .command(path: "/tmp/run.sh")),
            CustomWidget(title: "Inbox", systemImage: "folder", source: .folder(path: "/tmp"))
        )
    }

    @Test func exportLeavesCommandsOutAndKeepsOnlyTheWidgetsItUses() {
        let (web, command, folder) = customs()
        let layout = HomeLayout(widgets: [placement(.today, 3), custom(web.id), custom(command.id)])
        let archive = HomeArchive.make(layout: layout, customs: [web, command, folder])
        #expect(archive.widgets == [web], "the command, and the folder nothing uses, are left out")
        #expect(archive.layout.widgets.count == 2)
        #expect(!archive.layout.widgets.contains { $0.widget == .custom(command.id) })
    }

    @Test func importGivesWidgetsNewIDsAndNeverAcceptsACommand() throws {
        let (web, command, _) = customs()
        // A file someone edited by hand to include a command.
        let hostile = HomeArchive(
            layout: HomeLayout(widgets: [placement(.today, 3), custom(web.id), custom(command.id)]),
            widgets: [web, command])
        let plan = try HomeArchive.read(hostile.data()).importPlan()
        #expect(plan.widgets.count == 1)
        #expect(plan.widgets[0].id != web.id && plan.widgets[0].title == "Stocks")
        #expect(plan.widgets.allSatisfy { !$0.isCommand })
        #expect(plan.layout.widgets.contains { $0.widget == .custom(plan.widgets[0].id) })
        #expect(!plan.layout.widgets.contains { $0.widget == .custom(command.id) })
        #expect(plan.summary == "Adds 1 widget: Stocks (api.example.com)")
    }

    @Test func importDropsAWidgetThatIsntValid() throws {
        var insecure = customs().web
        insecure.source = .web(url: URL(string: "http://api.example.com")!, path: nil)
        let plan = HomeArchive(
            layout: HomeLayout(widgets: [placement(.today, 3), custom(insecure.id)]),
            widgets: [insecure]
        ).importPlan()
        #expect(plan.widgets.isEmpty)
    }

    @Test func anOlderFileWithoutWidgetsStillReads() throws {
        let layoutData = try JSONEncoder().encode(HomeLayout.default)
        let layout = String(decoding: layoutData, as: UTF8.self)
        let json = #"{"format":"MacIsland Home","version":1,"layout":\#(layout)}"#
        let read = try HomeArchive.read(Data(json.utf8))
        #expect(read.widgets.isEmpty && read.layout == .default)
    }
}

/// The drags, driven by points the way the views drive them: `gridFrame` and `bandFrame` are where the views say Home's grid and
/// the preview band are, and every point is in that space.
@MainActor
struct HomeCanvasTests {
    private let origin = CGPoint(x: 100, y: 120)

    private func makeEditor(_ layout: HomeLayout = .default) -> (HomeEditor, AppSettings, UndoManager) {
        let name = "MacIslandCanvas.\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: name)!)
        settings.setHomeLayout(layout)
        let editor = HomeEditor(settings: settings)
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        editor.gridFrame = CGRect(origin: origin, size: CGSize(width: 472, height: 138))
        editor.bandFrame = CGRect(x: 40, y: 60, width: 560, height: 280)
        return (editor, settings, undo)
    }

    /// The middle of a widget's box, where a person would pick it up.
    private func center(of id: UUID, in settings: AppSettings) -> CGPoint {
        let rect = settings.homeLayout.frames(catalog: settings.widgetDescriptor(for:))[id]!
        let frame = HomeGridSpec.frame(of: rect)
        return CGPoint(x: origin.x + frame.midX, y: origin.y + frame.midY)
    }

    /// Where the pointer is for a widget held at `grab` to have its top left at `cell`.
    private func point(_ cell: GridCell, holding grab: CGSize) -> CGPoint {
        let frame = HomeGridSpec.frame(of: GridRect(origin: cell, size: GridSize(1, 1)))
        return CGPoint(x: origin.x + frame.minX + grab.width, y: origin.y + frame.minY + grab.height)
    }

    private func gesture(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func movingMusicToTheFirstCellPutsMusicAndTodayFirst() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        let music = original.widgets[1]
        let held = center(of: music.id, in: settings)
        var ticks = 0
        editor.snapHaptic = { ticks += 1 }
        gesture(undo) {
            editor.beginMove(music.id, at: held)
            #expect(editor.selection == music.id)
            // Held where it is: nothing to show, and no tick.
            editor.update(to: CGPoint(x: held.x + 2, y: held.y))
            #expect(editor.live == nil && ticks == 0)
            let grab = CGSize(width: 116, height: 32)
            let top = point(GridCell(column: 0, row: 0), holding: grab)
            editor.update(to: top)
            #expect(ticks == 1)
            #expect(editor.live.map { Array(ids($0).prefix(2)) } == [.builtIn(.music), .builtIn(.today)])
            #expect(editor.message == "Release to place Music.")
            #expect(settings.homeLayout == original, "nothing is kept until it is let go")
            editor.update(to: CGPoint(x: top.x + 1, y: top.y + 1))
            #expect(ticks == 1, "the same place is not a new tick")
            #expect(editor.end(at: top))
        }
        #expect(Array(ids(settings.homeLayout).prefix(2)) == [.builtIn(.music), .builtIn(.today)])
        #expect(editor.gesture == nil && editor.live == nil && editor.message == nil)
        undo.undo()
        #expect(settings.homeLayout == original, "one gesture is one undo step")
        undo.redo()
        #expect(Array(ids(settings.homeLayout).prefix(2)) == [.builtIn(.music), .builtIn(.today)])
    }

    @Test func holdingAWidgetBackWhereItWasShowsTheOriginalLayout() {
        let (editor, settings, _) = makeEditor()
        let music = settings.homeLayout.widgets[1]
        let held = center(of: music.id, in: settings)
        editor.beginMove(music.id, at: held)
        editor.update(to: point(GridCell(column: 0, row: 0), holding: CGSize(width: 116, height: 32)))
        #expect(editor.live != nil)
        editor.update(to: held)
        #expect(editor.live == nil && editor.displayLayout == settings.homeLayout)
        editor.cancel()
    }

    @Test func aPointOutsideThePreviewPutsTheWidgetBack() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        let today = original.widgets[0]
        editor.beginMove(today.id, at: center(of: today.id, in: settings))
        editor.update(to: CGPoint(x: 900, y: 900))
        #expect(editor.live == nil && editor.message == nil, "nothing lands off the island")
        #expect(!editor.end(at: CGPoint(x: 900, y: 900)))
        #expect(settings.homeLayout == original && !undo.canUndo)
        #expect(editor.gesture == nil && editor.dragPoint == nil)
    }

    @Test func cancelChangesNothing() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        let music = original.widgets[1]
        editor.beginMove(music.id, at: center(of: music.id, in: settings))
        editor.update(to: point(GridCell(column: 0, row: 0), holding: CGSize(width: 116, height: 32)))
        #expect(editor.live != nil)
        #expect(editor.perform(.escape))
        #expect(editor.gesture == nil && editor.live == nil && editor.dragPoint == nil)
        #expect(settings.homeLayout == original && !undo.canUndo)
    }

    @Test func aWidgetFromAddWidgetsLandsWhereItIsHeld() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        gesture(undo) {
            editor.beginAdd(.builtIn(.weather), size: GridSize(1, 1), at: CGPoint(x: 700, y: 400))
            #expect(editor.dragging?.widget == .builtIn(.weather))
            // Into the room under the last row: the half of a 1 by 1 is 36 by 32.
            let grab = CGSize(width: 36, height: 32)
            editor.update(to: point(GridCell(column: 0, row: 2), holding: grab))
            #expect(editor.live?.rowsUsed() == 3 && editor.live.map { ids($0).last } == .builtIn(.weather))
            #expect(editor.end(at: point(GridCell(column: 0, row: 2), holding: grab)))
        }
        #expect(settings.homeLayout.isPlaced(.builtIn(.weather)))
        #expect(editor.selection == settings.homeLayout.widgets.last?.id)
        undo.undo()
        #expect(settings.homeLayout == original)
    }

    @Test func letGoOnTheWallpaperPutsTheWidgetBackWhereItWas() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        let music = original.widgets[1]
        // The island is 520 wide in the middle of the band; the rest of the band is wallpaper.
        editor.islandFrame = CGRect(x: 60, y: 60, width: 520, height: 276)
        let wallpaper = CGPoint(x: 50, y: 200)
        #expect(editor.bandFrame.contains(wallpaper) && !editor.islandFrame.contains(wallpaper))
        editor.beginMove(music.id, at: center(of: music.id, in: settings))
        editor.update(to: point(GridCell(column: 0, row: 0), holding: CGSize(width: 116, height: 32)))
        #expect(editor.live != nil, "inside the island it moves the others")
        editor.update(to: wallpaper)
        #expect(editor.live == nil, "and off it they go back")
        #expect(!editor.end(at: wallpaper))
        #expect(settings.homeLayout == original && !undo.canUndo, "nothing is removed or moved")
    }

    @Test func insideTheIslandStillPlacesEvenWhereItIsEmpty() {
        let (editor, settings, _) = makeEditor()
        let music = settings.homeLayout.widgets[1]
        editor.islandFrame = CGRect(x: 60, y: 60, width: 520, height: 276)
        editor.beginMove(music.id, at: center(of: music.id, in: settings))
        // Under the last row, still inside the island's outline: the room to grow.
        editor.update(to: point(GridCell(column: 0, row: 2), holding: CGSize(width: 116, height: 32)))
        #expect(editor.message == "Release to place Music.")
        editor.cancel()
    }

    @Test func aDragThatNeverHeardTheMouseUpEndsWhereThePointerLastWas() {
        let (editor, settings, undo) = makeEditor()
        let today = settings.homeLayout.widgets[0]
        editor.islandFrame = CGRect(x: 60, y: 60, width: 520, height: 276)
        undo.beginUndoGrouping()
        editor.beginMove(today.id, at: center(of: today.id, in: settings))
        editor.update(to: point(GridCell(column: 3, row: 0), holding: CGSize(width: 116, height: 32)))
        let shown = editor.live
        // Its view went away mid-drag, so nothing ever calls end: the mouse-up watch does.
        editor.endIfStuck()
        undo.endUndoGrouping()
        #expect(editor.gesture == nil && editor.dragPoint == nil && editor.message == nil)
        #expect(shown != nil && settings.homeLayout == shown, "what was shown is kept")
        let kept = settings.homeLayout
        editor.endIfStuck()
        #expect(settings.homeLayout == kept, "and a second call does nothing")
    }

    @Test func aNewDragCallsOffOneThatIsStaleInsteadOfBeingFrozenOut() {
        let (editor, settings, _) = makeEditor()
        let original = settings.homeLayout
        let today = original.widgets[0]
        let music = original.widgets[1]
        editor.beginMove(today.id, at: center(of: today.id, in: settings))
        editor.update(to: point(GridCell(column: 3, row: 0), holding: CGSize(width: 116, height: 32)))
        #expect(editor.live != nil)
        // The mouse is up (as it is in tests) but the gesture never ended: the next drag starts clean.
        editor.beginMove(music.id, at: center(of: music.id, in: settings))
        #expect(editor.dragging?.id == music.id && editor.live == nil)
        #expect(settings.homeLayout == original, "the stale drag changed nothing")
        editor.cancel()
    }

    @Test func aDragWhileTheMouseIsDownIsNotCalledOff() {
        let (editor, settings, _) = makeEditor()
        let today = settings.homeLayout.widgets[0]
        let music = settings.homeLayout.widgets[1]
        editor.isMouseDown = { true }
        editor.beginMove(today.id, at: center(of: today.id, in: settings))
        editor.beginMove(music.id, at: center(of: music.id, in: settings))
        #expect(editor.dragging?.id == today.id, "a drag that is going is left alone")
        editor.cancel()
    }

    @Test func aWidgetFromAddWidgetsLetGoOutsideThePreviewIsDropped() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        editor.beginAdd(.builtIn(.weather), size: GridSize(1, 1), at: CGPoint(x: 700, y: 400))
        editor.update(to: CGPoint(x: 700, y: 400))
        #expect(editor.live == nil)
        #expect(!editor.end(at: CGPoint(x: 700, y: 400)))
        #expect(settings.homeLayout == original && !undo.canUndo)
    }

    @Test func aFullHomeRefusesAndSaysWhy() {
        let (editor, settings, undo) = makeEditor(fullLayout)
        let before = settings.homeLayout
        let grab = CGSize(width: 36, height: 32)
        editor.beginAdd(.builtIn(.battery), size: GridSize(1, 1), at: CGPoint(x: 700, y: 400))
        editor.update(to: point(GridCell(column: 0, row: 0), holding: grab))
        #expect(editor.message?.contains("fit") == true && editor.live == nil)
        #expect(!editor.end(at: point(GridCell(column: 0, row: 0), holding: grab)))
        #expect(settings.homeLayout == before && !undo.canUndo)
        #expect(editor.refusal?.contains("fit") == true, "and it says so after the drop")
    }

    @Test func aWidgetBackFromNotShownComesBackAtItsLastSize() {
        let (editor, settings, _) = makeEditor()
        editor.undoManager = nil
        let pill = settings.homeLayout.widgets[3]
        editor.remove(pill.id)
        #expect(editor.addSize(for: .builtIn(.clockActions)) == GridSize(5, 1))
        #expect(editor.addSize(for: .builtIn(.weather)) == GridSize(1, 1), "never placed: its default")
    }

    @Test func aResizeSnapsToTheNearestSizeThatFits() {
        let (editor, settings, undo) = makeEditor()
        let original = settings.homeLayout
        let today = original.widgets[0]
        gesture(undo) {
            editor.beginResize(today.id)
            // A 3 by 3 box won't fit (Timers would have nowhere to go), so it snaps to the 3 by 2 beside it, and says so.
            editor.updateResize(to: CGPoint(x: origin.x + 232, y: origin.y + 212))
            #expect(editor.message == "3 \u{00D7} 3 won\u{2019}t fit")
            #expect(editor.live?.widgets[0].size == GridSize(3, 2))
            #expect(settings.homeLayout == original)
            // A box that is a size that fits names it.
            editor.updateResize(to: CGPoint(x: origin.x + 152, y: origin.y + 64))
            #expect(editor.message == "2 \u{00D7} 1" && editor.live?.widgets[0].size == GridSize(2, 1))
            editor.updateResize(to: CGPoint(x: origin.x + 232, y: origin.y + 138))
            #expect(editor.message == "3 \u{00D7} 2")
            #expect(editor.endResize())
        }
        #expect(settings.homeLayout.widgets[0].size == GridSize(3, 2))
        undo.undo()
        #expect(settings.homeLayout == original, "one resize is one undo step")
    }

    @Test func aResizeBackToTheSameSizeChangesNothing() {
        let (editor, settings, undo) = makeEditor()
        let today = settings.homeLayout.widgets[0]
        editor.beginResize(today.id)
        editor.updateResize(to: CGPoint(x: origin.x + 232, y: origin.y + 64))
        #expect(editor.live == nil && editor.message == "3 \u{00D7} 1")
        #expect(!editor.endResize() && !undo.canUndo)
    }

    @Test func theHandleIsFollowedNotThePointer() {
        let (editor, settings, _) = makeEditor()
        let today = settings.homeLayout.widgets[0]
        // Held 12 by 12 inside the bottom right corner: the box is the handle's, not the pointer's.
        editor.beginResize(today.id, at: CGPoint(x: origin.x + 232 - 12, y: origin.y + 64 - 12))
        editor.updateResize(to: CGPoint(x: origin.x + 232 - 12, y: origin.y + 138 - 12))
        #expect(editor.message == "3 \u{00D7} 2")
        editor.cancel()
    }

    @Test func thePreviewIslandGrowsWhileAWidgetIsHeldOverTheRoom() {
        let live = TestSupport.makeViewModel()
        live.settings.setHomeLayout(HomeLayout.presets[3].layout)
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        let editor = HomeEditor(settings: live.settings)
        editor.previewModel = preview
        editor.gridFrame = CGRect(origin: origin, size: CGSize(width: 472, height: 64))
        editor.bandFrame = CGRect(x: 40, y: 60, width: 560, height: 280)
        preview.show(PreviewContext(presentation: .expanded, tab: .home))
        let before = preview.viewModel.contentHeight(for: .home)
        editor.beginAdd(.builtIn(.weather), size: GridSize(1, 1), at: CGPoint(x: 700, y: 400))
        editor.update(to: point(GridCell(column: 0, row: 1), holding: CGSize(width: 36, height: 32)))
        #expect(preview.viewModel.contentHeight(for: .home) > before, "a new row makes Home taller while it is held")
        #expect(live.contentHeight(for: .home) == before, "the real island never sees the preview")
        editor.cancel()
        #expect(
            preview.viewModel.contentHeight(for: .home) == before, "and it shrinks back when the drag is called off")
    }
}
