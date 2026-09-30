import Foundation
import Testing

@testable import MacIsland

@MainActor
struct TabDragTests {
    private func makeSettings(left: [IslandModule], right: [IslandModule]) -> AppSettings {
        let name = "MacIslandTabDrag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.replaceTabs(left: left, right: right)
        return settings
    }

    @Test func draggingFromLeftOntoTheRightTabSwapsThem() {
        let settings = makeSettings(left: [.home, .media, .clock, .reminders, .tools], right: [.notes])
        #expect(settings.placeTab(.clock, before: .notes))
        // The right tab takes the dragged tab's place on the left.
        #expect(settings.leftTabs == [.home, .media, .notes, .reminders, .tools])
        #expect(settings.rightTabs == [.clock])
    }

    @Test func draggingOntoAnEmptyRightSideJustMoves() {
        let settings = makeSettings(left: [.home, .media, .clock], right: [])
        #expect(settings.moveTab(.media, toSide: .right))
        #expect(settings.leftTabs == [.home, .clock] && settings.rightTabs == [.media])
    }

    @Test func draggingOntoAFullRightSideSwapsWithItsTab() {
        let settings = makeSettings(left: [.home, .media], right: [.notes])
        #expect(settings.moveTab(.home, toSide: .right))
        #expect(settings.leftTabs == [.notes, .media] && settings.rightTabs == [.home])
    }

    @Test func fromTheRightOntoALeftTabWithRoomInsertsBeforeIt() {
        let settings = makeSettings(left: [.home, .media], right: [.notes])
        #expect(settings.placeTab(.notes, before: .media))
        #expect(settings.leftTabs == [.home, .notes, .media] && settings.rightTabs.isEmpty)
    }

    @Test func fromTheRightOntoAFullLeftSideSwaps() {
        let settings = makeSettings(left: [.home, .media, .clock, .reminders, .tools], right: [.notes])
        #expect(settings.placeTab(.notes, before: .clock))
        #expect(settings.leftTabs == [.home, .media, .notes, .reminders, .tools])
        #expect(settings.rightTabs == [.clock])
    }

    @Test func onTheSameSideTheDraggedTabTakesTheTargetsPlace() {
        let settings = makeSettings(left: [.home, .media, .clock, .reminders], right: [])
        settings.placeTab(.home, before: .clock)
        #expect(settings.leftTabs == [.media, .clock, .home, .reminders])
        settings.placeTab(.reminders, before: .media)
        #expect(settings.leftTabs == [.reminders, .media, .clock, .home])
    }

    @Test func aTabFromNotShownReplacesTheOneOnAFullSide() {
        let settings = makeSettings(left: [.home, .media, .clock, .reminders, .tools], right: [])
        #expect(settings.placeTab(.notes, before: .clock))
        #expect(settings.leftTabs == [.home, .media, .notes, .reminders, .tools])
        #expect(!settings.isInTabs(.clock), "the one it replaced goes to Not Shown")
    }

    @Test func aTabFromNotShownJoinsASideWithRoom() {
        let settings = makeSettings(left: [.home, .media], right: [])
        #expect(settings.placeTab(.notes, before: .media))
        #expect(settings.leftTabs == [.home, .notes, .media])
    }

    @Test func thereIsAlwaysAtLeastOneTabAndNothingIsDuplicated() {
        let settings = makeSettings(left: [.home], right: [.notes])
        settings.placeTab(.home, before: .notes)
        #expect(settings.tabs.count == 2 && Set(settings.tabs) == [.home, .notes])
        #expect(!settings.placeTab(.home, before: .home))
        #expect(!settings.placeTab(.home, before: .agents))
    }

    @Test func aDropIsRefusedOntoATabThatIsNotShown() {
        let settings = makeSettings(left: [.home, .media], right: [])
        #expect(!settings.placeTab(.home, before: .notes))
        #expect(settings.leftTabs == [.home, .media])
    }
}

@MainActor
struct PreviewNavigationTests {
    @Test func theArrowsStepThroughThePresentationsAndStopAtTheEnds() {
        let live = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.show(PreviewContext(presentation: .compact))
        #expect(!preview.canStep(-1) && preview.canStep(1))
        preview.step(1)
        #expect(preview.context.presentation == .peek)
        preview.step(1)
        #expect(preview.context.presentation == .banner)
        preview.step(1)
        #expect(preview.context.presentation == .expanded)
        #expect(!preview.canStep(1))
        preview.step(1)
        #expect(preview.context.presentation == .expanded)
        preview.step(-1)
        #expect(preview.context.presentation == .banner)
    }

    @Test func steppingKeepsWhatWasBeingLookedAt() {
        let live = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.show(PreviewContext(presentation: .banner, tab: .clock, event: .headphones))
        preview.step(1)
        #expect(preview.context.tab == .clock && preview.context.event == .headphones)
        #expect(preview.viewModel.selectedTab == .clock && preview.viewModel.presentation == .expanded)
    }

    @Test func clickingATabShowsItAndADropSwapsAndShowsTheDraggedOne() {
        let live = TestSupport.makeViewModel()
        live.settings.replaceTabs(left: [.home, .media, .clock], right: [.notes])
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        let editor = TabEditor(settings: live.settings)
        editor.preview = preview

        preview.show(PreviewContext(presentation: .compact))
        editor.select(.clock)
        #expect(preview.context.presentation == .expanded && preview.viewModel.selectedTab == .clock)

        #expect(editor.drop([IslandModule.media.rawValue], onto: .notes))
        #expect(live.settings.rightTabs == [.media] && live.settings.leftTabs == [.home, .notes, .clock])
        #expect(preview.viewModel.selectedTab == .media, "the dragged tab is the one shown")
        #expect(!editor.drop(["nonsense"], onto: .notes))
    }
}

@MainActor
struct TabSwapTests {
    private func makeSettings(left: [IslandModule], right: [IslandModule]) -> AppSettings {
        let name = "MacIslandTabSwap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.replaceTabs(left: left, right: right)
        return settings
    }

    @Test func aTabAcrossTheNotchSwapsPlacesWithTheOneItLandsOn() {
        let settings = makeSettings(left: [.home, .media, .clock], right: [.notes])
        #expect(settings.swapTab(.clock, with: .notes))
        #expect(settings.leftTabs == [.home, .media, .notes] && settings.rightTabs == [.clock])
    }

    @Test func swappingNeverMakesOrFillsASideEvenWhenThereIsRoom() {
        let settings = makeSettings(left: [.home, .media, .clock], right: [])
        // Nothing to replace on the right, so there is no swap to make: the strip can't take a tab into an empty side.
        #expect(!settings.swapTab(.home, with: .tools))
        #expect(settings.leftTabs == [.home, .media, .clock] && settings.rightTabs.isEmpty)
    }

    @Test func twoTabsOnTheSameSideTradePlacesAndNothingElseMoves() {
        let settings = makeSettings(left: [.home, .media, .clock, .reminders], right: [])
        #expect(settings.swapTab(.home, with: .clock))
        #expect(settings.leftTabs == [.clock, .media, .home, .reminders])
    }

    @Test func aTabFromNotShownReplacesOneAndThatOneIsHidden() {
        let settings = makeSettings(left: [.home, .media, .clock], right: [.reminders])
        #expect(settings.swapTab(.notes, with: .reminders))
        #expect(settings.rightTabs == [.notes] && !settings.isInTabs(.reminders))
        #expect(settings.tabs.count == 4)
    }

    @Test func onlyAShownTabCanBeReplaced() {
        let settings = makeSettings(left: [.home, .media], right: [])
        #expect(!settings.swapTab(.home, with: .notes))
        #expect(!settings.swapTab(.home, with: .home))
        #expect(settings.leftTabs == [.home, .media])
    }

    @Test func thePreviewSaysWhatItIsDoing() {
        let live = TestSupport.makeViewModel()
        live.settings.replaceTabs(left: [.home, .media, .clock], right: [.notes])
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        let editor = TabEditor(settings: live.settings)
        editor.preview = preview

        editor.setTarget(.notes, isTargeted: true)
        #expect(editor.hint == "Release to swap with Notes.")
        editor.setTarget(.notes, isTargeted: false)
        #expect(editor.hint == nil)

        editor.drop([IslandModule.clock.rawValue], onto: .notes)
        #expect(editor.hint == "Swapped Clock and Notes.")
        editor.drop([IslandModule.shelf.rawValue], onto: .notes)
        #expect(editor.hint == "Shelf replaced Notes, which is now in Not Shown.")
    }
}

@MainActor
struct NotShownTrayTests {
    private func makeEditor(left: [IslandModule], right: [IslandModule]) -> (TabEditor, AppSettings, IslandPreviewModel)
    {
        let live = TestSupport.makeViewModel()
        live.settings.replaceTabs(left: left, right: right)
        let preview = IslandPreviewModel(live: live.features)
        let editor = TabEditor(settings: live.settings)
        editor.preview = preview
        return (editor, live.settings, preview)
    }

    @Test func aTabFromTheTrayReplacesTheTabItIsDroppedOnAndThatOneLandsInTheTray() {
        let (editor, settings, preview) = makeEditor(left: [.home, .media, .clock], right: [.reminders])
        defer { preview.stop() }
        editor.beginDrag(.shelf)
        editor.setTarget(.reminders, isTargeted: true)
        #expect(editor.hint == "Release to replace Reminders with Shelf.")
        #expect(editor.drop(.shelf, onto: .reminders))
        #expect(settings.rightTabs == [.shelf] && !settings.isInTabs(.reminders))
        #expect(settings.hiddenModules.contains(.reminders), "it is now in the tray, in view")
        #expect(editor.hint == "Shelf replaced Reminders, which is now in Not Shown.")
    }

    @Test func theHintNamesBothTabsWhileYouHoldOneOverAnother() {
        let (editor, _, preview) = makeEditor(left: [.home, .media, .clock], right: [.reminders])
        defer { preview.stop() }
        editor.beginDrag(.media)
        editor.setTarget(.reminders, isTargeted: true)
        #expect(editor.hint == "Release to swap Media and Reminders.")
        editor.setTarget(.reminders, isTargeted: false)
        #expect(editor.hint == nil)
    }

    @Test func dropTabOnTheTrayHidesItAndItAppearsThere() {
        let (editor, settings, preview) = makeEditor(left: [.home, .media, .clock], right: [])
        defer { preview.stop() }
        editor.beginDrag(.media)
        editor.setOverTray(true)
        #expect(editor.hint == "Release to hide Media.")
        #expect(editor.hide(.media))
        #expect(!settings.isInTabs(.media) && settings.hiddenModules.contains(.media))
        #expect(editor.hint == "Media is now in Not Shown." && !editor.isOverTray)
    }

    @Test func theLastTabCantBeHiddenAndACancelledDragLeavesNothingBehind() {
        let (editor, settings, preview) = makeEditor(left: [.home], right: [])
        defer { preview.stop() }
        #expect(!editor.hide(.home))
        #expect(settings.isInTabs(.home) && editor.hint == "There has to be at least one tab.")
        #expect(!editor.hide(.notes), "a tab that is already hidden has nothing to hide")
    }

    @Test func clickingATrayTabAddsItOrSaysHowToMakeRoom() {
        let (editor, settings, preview) = makeEditor(left: [.home, .media], right: [])
        defer { preview.stop() }
        editor.add(.notes)
        #expect(settings.isInTabs(.notes) && editor.hint == "Notes is now a tab.")

        let full = makeEditor(left: [.home, .media, .clock, .reminders, .tools], right: [.notes])
        defer { full.2.stop() }
        full.0.add(.shelf)
        #expect(!full.1.isInTabs(.shelf))
        #expect(full.0.hint == "Tabs are full. Drag Shelf onto a tab to replace it.")
    }

    @Test func hidingTheTabBeingShownMovesThePreviewToAnother() {
        let (editor, _, preview) = makeEditor(left: [.home, .media, .clock], right: [])
        defer { preview.stop() }
        editor.select(.media)
        editor.hide(.media)
        #expect(preview.viewModel.selectedTab != .media)
    }
}

@MainActor
struct MenuBarViewTests {
    private func makePreview() -> (IslandPreviewModel, AppSettings) {
        let live = TestSupport.makeViewModel()
        return (IslandPreviewModel(live: live.features), live.settings)
    }

    @Test func menuBarIsAViewOnlyWhereItIsAllowed() {
        let (preview, _) = makePreview()
        defer { preview.stop() }
        #expect(!preview.presentations.contains(.menuBar))
        preview.show(PreviewContext(presentation: .expanded))
        #expect(!preview.canStep(1), "Expanded is the last view elsewhere")

        preview.allowsMenuBar = true
        #expect(preview.presentations == [.compact, .peek, .banner, .expanded, .menuBar])
        #expect(preview.canStep(1))
        preview.step(1)
        #expect(preview.context.presentation == .menuBar)
        #expect(!preview.canStep(1) && preview.canStep(-1))
        preview.step(-1)
        #expect(preview.context.presentation == .expanded)
    }

    @Test func noPaneStartsOnTheMenuBar() {
        for pane in SettingsPane.allCases {
            #expect(pane.previewContext?.presentation != .menuBar, "\(pane)")
        }
    }

    @Test func theMenuBarViewLeavesTheIslandAsItWasAndRemembersItsOwnModule() {
        let (preview, settings) = makePreview()
        defer { preview.stop() }
        preview.allowsMenuBar = true
        preview.show(PreviewContext(presentation: .expanded, tab: .notes))
        settings.setInMenuBar(.clock, true)
        preview.showMenuBar(.clock)
        #expect(preview.context.presentation == .menuBar && preview.context.menuBarTab == .clock)
        #expect(preview.menuBarProgress == 1)
        // The island did not change on its way out: still expanded, on the same tab.
        #expect(preview.viewModel.state == .expanded && preview.viewModel.selectedTab == .notes)
        #expect(preview.context.tab == .notes, "the island's own tab is kept for the way back")
        preview.step(-1)
        #expect(preview.menuBarProgress == 0 && preview.context.tab == .notes)
        #expect(preview.viewModel.selectedTab == .notes)
        settings.setInMenuBar(.clock, false)
    }

    @Test func steppingIntoTheMenuBarKeepsTheTabChosenBefore() {
        let (preview, _) = makePreview()
        defer { preview.stop() }
        preview.allowsMenuBar = true
        preview.show(PreviewContext(presentation: .expanded, tab: .notes))
        preview.step(1)
        #expect(preview.context.tab == .notes)
    }
}

@MainActor
struct MenuBarPreviewingTests {
    @Test func aModuleCanBePreviewedInTheMenuBarWithoutTurningItOn() {
        let live = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.allowsMenuBar = true
        #expect(!live.settings.isInMenuBar(.reminders))
        preview.showMenuBar(.reminders)
        #expect(preview.context.menuBarTab == .reminders)
        #expect(!live.settings.isInMenuBar(.reminders), "looking at it adds nothing to the menu bar")
    }
}
