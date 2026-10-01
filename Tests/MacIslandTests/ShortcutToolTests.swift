import Foundation
import Testing

@testable import MacIsland

@MainActor
struct ShortcutToolTests {
    private func makeSettings(suite: String = "MacIslandShortcutTools.\(UUID().uuidString)") -> (AppSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppSettings(defaults: defaults), defaults)
    }

    /// Lists these Shortcuts through the view model, as the Tools tab does when it appears, and waits for the answer.
    private func install(_ names: [String], on viewModel: IslandViewModel) async {
        viewModel.shortcutLister = { names }
        viewModel.refreshInstalledShortcuts()
        for _ in 0..<100 where viewModel.installedShortcuts != Set(names) { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func tool(_ shortcut: String = "Wind Down", title: String = "Wind Down") -> ShortcutTool {
        ShortcutTool(shortcut: shortcut, title: title)
    }

    // MARK: Identity

    @Test func aToolIDIsABuiltInOrAWellFormedShortcutTool() {
        #expect(ToolID.allCases.count == 9)
        #expect(ToolID.keepAwake.rawValue == "keepAwake" && ToolID(rawValue: "mirror") == .mirror)
        #expect(ToolID(rawValue: "nonsense") == nil && ToolID(rawValue: "shortcut:not-a-uuid") == nil)
        let id = UUID()
        let custom = ToolID(shortcut: id)
        #expect(ToolID(rawValue: custom.rawValue) == custom && custom.shortcutID == id && !custom.isBuiltIn)
        #expect(ToolID.keepAwake.shortcutID == nil && ToolID.keepAwake.isBuiltIn)
    }

    @Test func toolIDsKeepTheirStoredShape() throws {
        // A built-in is stored as its bare name, exactly as when this was an enum, so nothing already saved breaks.
        let data = try JSONEncoder().encode([ToolID.keepAwake, ToolID(shortcut: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)])
        #expect(
            String(data: data, encoding: .utf8)
                == #"["keepAwake","shortcut:00000000-0000-0000-0000-000000000001"]"#)
        #expect(try JSONDecoder().decode([ToolID].self, from: data).count == 2)
        #expect(throws: (any Error).self) { try JSONDecoder().decode([ToolID].self, from: Data(#"["bogus"]"#.utf8)) }
    }

    // MARK: Settings

    @Test func aToolIsValidWithAShortcutALabelAndARealSymbol() {
        #expect(tool().isValid)
        #expect(!tool("", title: "x").isValid && !tool("a", title: "  ").isValid)
        var bad = tool()
        bad.systemImage = "not.a.real.symbol.at.all"
        #expect(!bad.isValid)
        #expect(tool("  Wind Down ", title: "A very long label indeed").cleaned.title.count == ShortcutTool.maxTitleLength)
        #expect(tool().systemImage == "bolt.fill")
    }

    @Test func toolsAreKeptAndRestoredAcrossLaunches() {
        let (settings, defaults) = makeSettings()
        let made = tool()
        #expect(settings.saveShortcutTool(made))
        #expect(AppSettings(defaults: defaults).shortcutTools == [made])
        // Saving again with the same id replaces it, and keeps it one.
        var renamed = made
        renamed.title = "Wind"
        #expect(settings.saveShortcutTool(renamed) && settings.shortcutTools.map(\.title) == ["Wind"])
        #expect(AppSettings(defaults: defaults).shortcutTools.map(\.title) == ["Wind"])
    }

    @Test func thereIsRoomForTwoAndAnInvalidOneIsRefused() {
        let (settings, _) = makeSettings()
        #expect(settings.canAddShortcutTool)
        #expect(settings.saveShortcutTool(tool("A", title: "A")) && settings.saveShortcutTool(tool("B", title: "B")))
        #expect(!settings.canAddShortcutTool)
        #expect(!settings.saveShortcutTool(tool("C", title: "C")), "the Tools tab is full")
        #expect(settings.shortcutTools.count == AppSettings.maxShortcutTools)
        // An edit of one that is there still works when full.
        var edited = settings.shortcutTools[0]
        edited.title = "Edited"
        #expect(settings.saveShortcutTool(edited))
        #expect(!makeSettings().0.saveShortcutTool(tool("", title: "")))
    }

    @Test func allToolsHasTheBuiltInsThenTheirsAndIsKnownSaysWhichExist() {
        let (settings, _) = makeSettings()
        let made = tool()
        settings.saveShortcutTool(made)
        #expect(settings.allTools == ToolID.allCases + [made.toolID])
        #expect(settings.isKnown(.keepAwake) && settings.isKnown(made.toolID))
        #expect(!settings.isKnown(ToolID(shortcut: UUID())))
        #expect(settings.shortcutTool(for: made.toolID) == made && settings.shortcutTool(for: .mirror) == nil)
    }

    // MARK: The pinned row

    @Test func aShortcutToolCanBePinnedAndIsFilledInLikeAnyOther() {
        let (settings, _) = makeSettings()
        let made = tool()
        settings.saveShortcutTool(made)
        settings.togglePin(made.toolID)
        #expect(settings.visiblePinned.contains(made.toolID) && settings.visiblePinned.count == 6)
        #expect(settings.isPinned(made.toolID))
        settings.togglePin(made.toolID)
        #expect(!settings.isPinned(made.toolID) && settings.visiblePinned.count == 6)
    }

    @Test func removingAToolTakesItOffTheRowAndTheRowStaysFull() {
        let (settings, defaults) = makeSettings()
        let made = tool()
        settings.saveShortcutTool(made)
        settings.togglePin(made.toolID)
        settings.removeShortcutTool(made.id)
        #expect(!settings.visiblePinned.contains(made.toolID) && settings.visiblePinned.count == 6)
        #expect(!settings.pinnedTools.contains(made.toolID))
        #expect(AppSettings(defaults: defaults).shortcutTools.isEmpty)
    }

    @Test func aPinnedToolWhoseRecordIsGoneIsDroppedOnLaunch() {
        let (_, defaults) = makeSettings()
        let ghost = ToolID(shortcut: UUID())
        defaults.set([ToolID.mirror.rawValue, ghost.rawValue], forKey: "pinnedTools")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.pinnedTools == [.mirror])
        #expect(!settings.visiblePinned.contains(ghost))
    }

    @Test func theRowShowsEveryToolOnlyWhenThereIsRoomForAll() {
        let (settings, _) = makeSettings()
        settings.pinLimit = .eight
        #expect(!settings.rowShowsEveryTool)
        #expect(settings.allTools.count == 9)
    }

    @Test func quickToolsIncludeTheirsAndLeaveOutOnesThatAreGone() {
        let (settings, _) = makeSettings()
        let made = tool()
        settings.saveShortcutTool(made)
        let ghost = ToolID(shortcut: UUID())
        let all = settings.allTools
        #expect(QuickActionsGrid.tools(for: GridSize(6, 2), chosen: nil, pinned: [], all: all) == all)
        let chosen = QuickActionsGrid.tools(for: GridSize(3, 1), chosen: [ghost, made.toolID], pinned: [], all: all)
        #expect(chosen.first == made.toolID && !chosen.contains(ghost) && chosen.count == 6)
        #expect(QuickActionsGrid.toolCount(for: GridSize(6, 2), total: all.count) == 10)
        #expect(WidgetInspector.filled([ghost], to: 4, from: all).count == 4)
    }

    // MARK: Archive

    @Test func toolsGoThroughTheSettingsFile() throws {
        let (original, _) = makeSettings()
        let first = tool("A", title: "A")
        let second = tool("B", title: "B")
        original.saveShortcutTool(first)
        original.saveShortcutTool(second)
        original.togglePin(second.toolID)
        let data = try SettingsArchive.make(from: original).data()

        let (target, _) = makeSettings()
        target.restore(try SettingsArchive.read(data))
        #expect(target.shortcutTools == [first, second])
        #expect(target.visiblePinned.contains(second.toolID))
    }

    @Test func anImportedFileCannotOverfillOrSlipInAnInvalidTool() throws {
        var archive = SettingsArchive()
        archive.shortcutTools = [tool("A", title: "A"), tool("", title: ""), tool("B", title: "B"), tool("C", title: "C")]
        let (settings, _) = makeSettings()
        settings.restore(archive)
        #expect(settings.shortcutTools.map(\.shortcut) == ["A", "B"])
    }

    @Test func resetAllRemovesThem() {
        let (settings, _) = makeSettings()
        settings.saveShortcutTool(tool())
        settings.resetAll()
        #expect(settings.shortcutTools.isEmpty)
    }

    // MARK: On the Tools tab

    @Test func aShortcutToolIsAButtonUnlessItsShortcutIsGone() async {
        let viewModel = TestSupport.makeViewModel()
        let made = tool()
        viewModel.settings.saveShortcutTool(made)
        let catalog = ToolCatalog(viewModel: viewModel)
        let item = catalog.item(for: made.toolID)
        #expect(item.title == "Wind Down" && item.systemImage == "bolt.fill" && item.isAvailable && !item.isOn)
        #expect(item.label == "Run Wind Down")

        await install(["Something Else"], on: viewModel)
        #expect(!catalog.item(for: made.toolID).isAvailable, "renamed or deleted: dimmed")
        await install(["Wind Down"], on: viewModel)
        #expect(catalog.item(for: made.toolID).isAvailable)
        #expect(!catalog.item(for: ToolID(shortcut: UUID())).isAvailable, "a record that is gone")
    }

    @Test func runningOneShowsWorkThenDoneAndCannotBeStartedTwice() async {
        let viewModel = TestSupport.makeViewModel()
        let made = tool()
        viewModel.settings.saveShortcutTool(made)
        var runs: [String] = []
        viewModel.shortcutRunner = { name in
            runs.append(name)
            try? await Task.sleep(for: .milliseconds(60))
            return true
        }
        viewModel.runShortcutTool(made)
        viewModel.runShortcutTool(made)
        #expect(viewModel.runningShortcutTools == [made.id])
        #expect(ToolCatalog(viewModel: viewModel).item(for: made.toolID).isOn)
        #expect(viewModel.work.current != nil, "the blue working activity")
        for _ in 0..<100 where !viewModel.runningShortcutTools.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(runs == ["Wind Down"] && viewModel.runningShortcutTools.isEmpty && viewModel.work.current == nil)
        #expect(viewModel.alert?.text == "Done" && viewModel.alert?.tint == Theme.Tint.positive)
    }

    @Test func aFailureIsARedBannerNamingTheShortcut() async {
        let viewModel = TestSupport.makeViewModel()
        let made = tool()
        viewModel.settings.saveShortcutTool(made)
        viewModel.shortcutRunner = { _ in false }
        viewModel.runShortcutTool(made)
        for _ in 0..<100 where viewModel.banner == nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(viewModel.banner?.title.contains("Wind Down") == true && viewModel.banner?.tint == Theme.Tint.attention)
        #expect(viewModel.runningShortcutTools.isEmpty)
    }

    @Test func aMissingShortcutSaysSoAndOffersToEditTheToolInsteadOfRunning() async {
        let viewModel = TestSupport.makeViewModel()
        let made = tool()
        viewModel.settings.saveShortcutTool(made)
        var ran = false
        viewModel.shortcutRunner = { _ in
            ran = true
            return true
        }
        await install(["Other"], on: viewModel)
        var opened: [(SettingsPane, UUID?)] = []
        viewModel.onOpenSettings = { opened.append(($0, $1)) }
        viewModel.runShortcutTool(made)
        #expect(!ran && viewModel.banner?.title.contains("Isn") == true)
        viewModel.banner?.actions.first?.perform()
        #expect(opened.first?.0 == .tabs && viewModel.settings.requestedShortcutToolEdit == made.id)
    }

    @Test func installedShortcutsAreListedOnlyWhenThereIsAToolAndAnEmptyAnswerSaysNothing() async {
        let viewModel = TestSupport.makeViewModel()
        var lists = 0
        viewModel.shortcutLister = {
            lists += 1
            return ["A", "B"]
        }
        viewModel.refreshInstalledShortcuts()
        #expect(lists == 0 && viewModel.installedShortcuts == nil, "no tools, nothing to check")
        viewModel.settings.saveShortcutTool(tool("A", title: "A"))
        viewModel.refreshInstalledShortcuts()
        for _ in 0..<100 where viewModel.installedShortcuts == nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(viewModel.installedShortcuts == ["A", "B"])
        viewModel.shortcutLister = { [] }
        viewModel.refreshInstalledShortcuts()
        for _ in 0..<100 where viewModel.installedShortcuts != nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(viewModel.installedShortcuts == nil, "an empty list is shortcuts failing to answer as often as not")
    }
}
