import AppKit
import Carbon.HIToolbox
import Testing

@testable import MacIsland

struct OnboardingFlowTests {
    private func setup(
        shortcut: KeyCombo? = .openDefault, hasNotch: Bool = true, tabs: [IslandModule] = IslandModule.defaultTabs,
        hidden: [IslandModule] = [.shelf, .notes], drag: DragTarget = .shelfAndAirDrop, screenshots: Bool = true
    ) -> GuideSetup {
        GuideSetup(
            openShortcut: shortcut, hasNotch: hasNotch, tabs: tabs, hiddenModules: hidden, dragTarget: drag,
            addsScreenshots: screenshots)
    }

    // MARK: Flow

    @Test func everyStepForAFreshInstall() {
        let flow = OnboardingFlow.make(seen: 0, replay: false, settled: [])
        #expect(flow.steps.map(\.id) == GuideStepID.allCases)
        #expect(flow.count == 19)
    }

    @Test func permissionStepsAreLeftOutWhenSettled() {
        let flow = OnboardingFlow.make(seen: 0, replay: false, settled: Set(AccessKind.allCases))
        #expect(flow.count == 9)
        #expect(flow.steps.allSatisfy { $0.id.accessKind == nil })
        // One settled permission leaves only its own step out, and the rest keep their order.
        let some = OnboardingFlow.make(seen: 0, replay: false, settled: [.camera, .reminders])
        #expect(some.count == 17)
        #expect(!some.steps.contains { $0.id == .camera || $0.id == .reminders })
        #expect(some.steps.contains { $0.id == .calendars } && some.steps.contains { $0.id == .microphone })
    }

    @Test func thePermissionStepsComeInTheOrderTheyAreAsked() {
        let order = GuideStep.all.compactMap(\.id.accessKind)
        #expect(
            order == [
                .calendars, .reminders, .bluetooth, .downloads, .camera, .microphone, .screenRecording, .accessibility,
                .focus, .automation,
            ])
        #expect(Set(order) == Set(AccessKind.allCases))
        for kind in AccessKind.allCases { #expect(GuideStepID(kind).accessKind == kind) }
        // They sit between the tour of the island and the last step.
        #expect(GuideStep.all.first?.id == .welcome && GuideStep.all.last?.id == .finish)
    }

    @Test func replayShowsEveryStep() {
        let flow = OnboardingFlow.make(seen: 1, replay: true, settled: [])
        #expect(flow.steps.map(\.id) == GuideStepID.allCases)
    }

    @Test func aRerunShowsOnlyWhatIsNewThenTheLastStep() {
        // Nothing has `since` above 1 yet, so someone who saw version 1 sees just the last step.
        let flow = OnboardingFlow.make(seen: 1, replay: false, settled: [])
        #expect(flow.steps.map(\.id) == [.finish])
        #expect(flow.isFirst && flow.isLast)
    }

    @Test func nextAndBackClamp() {
        var flow = OnboardingFlow.make(seen: 0, replay: false, settled: [])
        flow.back()
        #expect(flow.isFirst && flow.current.id == .welcome)
        for _ in 0..<20 { flow.next() }
        #expect(flow.isLast && flow.current.id == .finish)
        flow.back()
        #expect(flow.current.id == .automation)
    }

    @Test func everyStepHasItsStage() {
        for step in GuideStep.all {
            #expect((step.stage == nil) == (step.id == .menuBar), "\(step.id)")
        }
    }

    // MARK: Copy

    @Test func everyStepHasATitleAndACopy() {
        for id in GuideStepID.allCases {
            #expect(!GuideCopy.title(id).isEmpty)
            #expect(!GuideCopy.body(id, setup: setup()).isEmpty)
        }
    }

    @Test func copyFollowsTheShortcut() {
        let on = setup()
        let off = setup(shortcut: nil)
        #expect(GuideCopy.body(.open, setup: on).contains("\u{2303}\u{2325}Space"))
        #expect(!GuideCopy.body(.open, setup: off).contains("From anywhere"))
        #expect(!GuideCopy.body(.open, setup: off).contains("\u{2303}"))
        #expect(GuideCopy.showsShortcutCaps(.open, setup: on))
        #expect(!GuideCopy.showsShortcutCaps(.open, setup: off))
        #expect(GuideCopy.body(.tabs, setup: on).contains("\u{2190} and \u{2192}"))
        #expect(!GuideCopy.body(.tabs, setup: off).contains("\u{2190}"))
        #expect(GuideCopy.keyCaps(.tabs, setup: on) == ["\u{2190}", "\u{2192}"])
        #expect(GuideCopy.keyCaps(.tabs, setup: off).isEmpty)
        #expect(GuideCopy.body(.close, setup: on).contains("opened it from the keyboard"))
        #expect(!GuideCopy.body(.close, setup: off).contains("keyboard"))
        #expect(GuideCopy.body(.close, setup: off).contains("typing in it"))
        #expect(GuideCopy.keyCaps(.close, setup: off) == ["Esc"])
    }

    @Test func copyFollowsTheDragTarget() {
        #expect(GuideCopy.body(.drop, setup: setup(drag: .shelfAndAirDrop)).contains("left half"))
        #expect(GuideCopy.body(.drop, setup: setup(drag: .shelfOnly)).contains("keep it on the Shelf"))
        #expect(!GuideCopy.body(.drop, setup: setup(drag: .shelfOnly)).contains("AirDrop"))
        #expect(GuideCopy.body(.drop, setup: setup(drag: .airDropOnly)).contains("to AirDrop it"))
        let off = GuideCopy.body(.drop, setup: setup(drag: .nothing))
        #expect(off.contains("is off") && off.contains("Settings \u{2192} Shelf"))
        let dropStep = GuideStep.all.first { $0.id == .drop }!
        #expect(GuideCopy.practice(for: dropStep, setup: setup(drag: .nothing)) == nil)
        #expect(GuideCopy.practice(for: dropStep, setup: setup()) == .dropFile)
    }

    @Test func theScreenshotSentenceFollowsTheSetting() {
        #expect(GuideCopy.body(.drop, setup: setup(screenshots: true)).contains("screenshots"))
        #expect(!GuideCopy.body(.drop, setup: setup(screenshots: false)).contains("screenshots"))
    }

    @Test func modulesCopyNamesTheTabs() {
        let text = GuideCopy.body(.modules, setup: setup())
        #expect(text.hasPrefix("Your tabs are Home, Media, Clock, Reminders"))
        #expect(text.contains("Shelf and Notes open when you need them."))
        let moved = GuideCopy.body(
            .modules,
            setup: setup(tabs: [.home, .media, .clock, .notes, .tools], hidden: [.shelf, .reminders]))
        #expect(moved.contains("Notes"))
        #expect(moved.contains("Shelf and Reminders open when you need them."))
    }

    @Test func oneHiddenModuleIsSingular() {
        let text = GuideCopy.body(.modules, setup: setup(hidden: [.notes]))
        #expect(text.contains("Notes opens when you need it."))
    }

    @Test func nothingHiddenLeavesThatSentenceOut() {
        let text = GuideCopy.body(.modules, setup: setup(hidden: []))
        #expect(!text.contains("when you need"))
        #expect(text.hasSuffix("Choose one to see it."))
    }

    @Test func noNotchSaysTopCenter() {
        let none = setup(hasNotch: false)
        #expect(GuideCopy.body(.peek, setup: none).contains("the top center of the screen"))
        #expect(!GuideCopy.body(.peek, setup: none).contains("the notch"))
    }

    @Test func aModuleOutsideTheTabsAddsItsOtherWayIn() {
        #expect(GuideCopy.moduleLines(.notes, inTabs: true).count == 1)
        #expect(GuideCopy.moduleLines(.notes, inTabs: false).count == 2)
        #expect(GuideCopy.moduleLines(.tools, inTabs: false).count == 1)
        for module in IslandModule.allCases where module.isAvailable {
            #expect(!GuideCopy.moduleLines(module, inTabs: true)[0].isEmpty, "\(module)")
        }
    }

    @Test func thePrimaryButtonSaysWhereYouAre() {
        #expect(GuideCopy.primaryTitle(.welcome, isLast: false) == "Get Started")
        #expect(GuideCopy.primaryTitle(.peek, isLast: false) == "Continue")
        #expect(GuideCopy.primaryTitle(.finish, isLast: true) == "Done")
    }

    // MARK: Practice

    private func island(
        _ state: IslandViewModel.State, tab: IslandModule = .home, drag: Bool = false
    ) -> PracticeGoal.Island {
        PracticeGoal.Island(state: state, tab: tab, isFileDragActive: drag)
    }

    @Test func peekIsMetByAPeekOrAnOpen() {
        #expect(PracticeGoal.peek.isMet(from: island(.compact), to: island(.peek)))
        #expect(PracticeGoal.peek.isMet(from: island(.compact), to: island(.expanded)))
        #expect(!PracticeGoal.peek.isMet(from: island(.peek), to: island(.compact)))
    }

    @Test func openNeedsTheExpandedIsland() {
        #expect(PracticeGoal.open.isMet(from: island(.peek), to: island(.expanded)))
        #expect(!PracticeGoal.open.isMet(from: island(.compact), to: island(.peek)))
    }

    @Test func changeTabIsNotMetByTheFirstOpen() {
        #expect(!PracticeGoal.changeTab.isMet(from: island(.compact), to: island(.expanded, tab: .media)))
        #expect(PracticeGoal.changeTab.isMet(from: island(.expanded), to: island(.expanded, tab: .media)))
        #expect(!PracticeGoal.changeTab.isMet(from: island(.expanded), to: island(.expanded)))
    }

    @Test func closeIsNotMetWhenTheIslandWasAlreadyCompact() {
        #expect(PracticeGoal.close.isMet(from: island(.expanded), to: island(.compact)))
        #expect(PracticeGoal.close.isMet(from: island(.peek), to: island(.compact)))
        #expect(!PracticeGoal.close.isMet(from: island(.compact), to: island(.compact)))
    }

    @Test func dropFileNeedsTheDragToStart() {
        #expect(PracticeGoal.dropFile.isMet(from: island(.compact), to: island(.compact, drag: true)))
        #expect(!PracticeGoal.dropFile.isMet(from: island(.compact, drag: true), to: island(.compact, drag: true)))
        #expect(!PracticeGoal.dropFile.isMet(from: island(.compact, drag: true), to: island(.compact)))
    }
}

@MainActor
struct OnboardingModelTests {
    /// Everything a model needs, over test doubles: a private defaults suite, a stub for permissions, and a live view model
    /// whose sample features feed the stage.
    private struct Rig {
        let model: OnboardingModel
        let state: OnboardingState
        let access: StubAccess
        let reference: IslandViewModel
        let ends: Ends
        let monitorStarts: Counter
        let settingsOpened: Counter
    }

    private final class Ends { var list: [GuideEnding] = [] }
    private final class Counter { var count = 0 }

    private func makeRig(existing: Bool = false, replay: Bool = false, access: StubAccess? = nil) -> Rig {
        let access = access ?? StubAccess()
        let suite = "MacIslandOnboardingModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = OnboardingState(defaults: defaults, isExistingInstall: { existing })
        let reference = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: reference.features)
        let ends = Ends()
        let starts = Counter()
        let opened = Counter()
        let accessModel = AccessModel(provider: access, settings: reference.settings, onBluetoothAllowed: {})
        let model = OnboardingModel(
            state: state, settings: reference.settings, geometry: { reference.geometry }, preview: preview,
            access: accessModel, replay: replay,
            startDeferredMonitors: { starts.count += 1 }, openSettings: { opened.count += 1 },
            onEnd: { ends.list.append($0) })
        return Rig(
            model: model, state: state, access: access, reference: reference, ends: ends, monitorStarts: starts,
            settingsOpened: opened)
    }

    private func island(_ state: IslandViewModel.State, tab: IslandModule = .home, drag: Bool = false)
        -> PracticeGoal.Island
    {
        PracticeGoal.Island(state: state, tab: tab, isFileDragActive: drag)
    }

    @Test func startsOnTheWelcomeWithItsStage() {
        let rig = makeRig()
        defer { rig.model.stop() }
        #expect(rig.model.step.id == .welcome)
        #expect(rig.model.preview.context.presentation == .compact)
        #expect(rig.model.primaryTitle == "Get Started")
    }

    @Test func aPracticeStepStartsBeforeTheAnswer() {
        let rig = makeRig()
        defer { rig.model.stop() }
        let stage = rig.model.stageIsland
        // Peeking and opening are done to a closed island.
        rig.model.next()
        #expect(rig.model.step.id == .peek && stage.state == .compact)
        rig.model.next()
        #expect(rig.model.step.id == .open && stage.state == .compact)
        // Changing the tab and closing are done to an open one, on Home.
        rig.model.next()
        #expect(rig.model.step.id == .tabs && stage.state == .expanded && stage.selectedTab == .home)
        rig.model.next()
        #expect(rig.model.step.id == .close && stage.state == .expanded && stage.selectedTab == .home)
        // Dragging a file is done to a closed island, with no drop target showing yet.
        while rig.model.step.id != .drop { rig.model.next() }
        #expect(stage.state == .compact && !stage.isFileDragActive)
    }

    @Test func goingBackIsNotDoingTheExercise() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while rig.model.step.id != .close { rig.model.next() }
        // Swipe to another tab on the Fold It Away step, then go back to Change Tabs: Home comes back, which is not a swipe.
        rig.model.stageIsland.selectAdjacentTab(1)
        rig.model.observe(PracticeGoal.Island(rig.model.stageIsland))
        rig.model.back()
        rig.model.observe(PracticeGoal.Island(rig.model.stageIsland))
        #expect(rig.model.step.id == .tabs)
        #expect(!rig.model.isPracticeMet)
    }

    @Test func theModulesStageFollowsTheChosenChip() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while rig.model.step.id != .modules { rig.model.next() }
        rig.model.choose(.notes)
        #expect(rig.model.preview.context.tab == .notes)
        #expect(rig.model.preview.context.presentation == .expanded)
    }

    @Test func theMenuBarStepSlidesToTheMenuBarAndBackComes() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while rig.model.step.id != .menuBar { rig.model.next() }
        #expect(rig.model.preview.context.presentation == .menuBar)
        rig.model.back()
        #expect(rig.model.preview.context.presentation != .menuBar)
    }

    @Test func aPracticeCheckTurnsGreenOnTheRightChangeOnly() {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.next()  // peek
        #expect(rig.model.practice == .peek)
        rig.model.observe(island(.compact, drag: true))
        #expect(!rig.model.isPracticeMet)
        rig.model.observe(island(.peek))
        #expect(rig.model.isPracticeMet)
    }

    @Test func aPracticeCheckNeverBlocksOrAdvances() {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.next()
        rig.model.observe(island(.peek))
        #expect(rig.model.step.id == .peek)
        rig.model.next()
        #expect(rig.model.step.id == .open)
    }

    @Test func aMetCheckStaysMetWhenGoingBack() {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.next()
        rig.model.observe(island(.peek))
        rig.model.next()
        rig.model.back()
        #expect(rig.model.isPracticeMet)
    }

    // MARK: The stage island answers like the real one

    @Test func restingThePointerOnTheStageIslandPeeksIt() async {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.next()  // Rest the Pointer to Peek
        let stage = rig.model.stageIsland
        #expect(stage.state == .compact)
        stage.setHovering(true)
        for _ in 0..<100 where stage.state != .peek { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(stage.state == .peek)
        #expect(PracticeGoal.peek.isMet(from: island(.compact), to: PracticeGoal.Island(stage)))
    }

    @Test func aSwipeOnTheStageDoesWhatItDoesOnTheRealIsland() {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.next()
        let stage = rig.model.stageIsland
        stage.perform(.down)
        #expect(stage.state == .expanded)
        stage.perform(.right)
        #expect(stage.selectedTab == .media)
        stage.perform(.left)
        #expect(stage.selectedTab == .home)
        stage.perform(.up)
        #expect(stage.state == .compact)
    }

    @Test func swipingTurnedOffInSettingsLeavesTheStageAlone() {
        let rig = makeRig()
        defer { rig.model.stop() }
        // The stage shares the live settings, so the choice reaches it as it reaches the island.
        rig.reference.settings.swipesEnabled = false
        rig.model.next()
        rig.model.stageIsland.perform(.down)
        #expect(rig.model.stageIsland.state == .compact)
    }

    @Test func escClosesTheStageIslandAndNeverTheGuide() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while rig.model.step.id != .close { rig.model.next() }
        let stage = rig.model.stageIsland
        #expect(stage.state == .expanded)
        #expect(rig.model.handleKey(UInt16(kVK_Escape)))
        #expect(stage.state == .compact)
        // With nothing open Esc is still taken, so it never reaches the window's own close.
        #expect(rig.model.handleKey(UInt16(kVK_Escape)))
        #expect(stage.state == .compact)
        #expect(rig.ends.list.isEmpty)
    }

    @Test func theArrowKeysChangeTheTabOfAnOpenStageIsland() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while rig.model.step.id != .tabs { rig.model.next() }
        let stage = rig.model.stageIsland
        #expect(rig.model.handleKey(UInt16(kVK_RightArrow)))
        #expect(stage.selectedTab == .media)
        #expect(rig.model.handleKey(UInt16(kVK_LeftArrow)))
        #expect(stage.selectedTab == .home)
        stage.closePinned()
        #expect(!rig.model.handleKey(UInt16(kVK_RightArrow)))
        #expect(stage.selectedTab == .home)
    }

    @Test func theOpenShortcutOpensAndPinsTheStageIsland() {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.next()
        rig.model.next()  // Open It
        let stage = rig.model.stageIsland
        #expect(rig.model.toggleStageFromKeyboard())
        #expect(stage.state == .expanded && stage.isPinnedOpen)
        #expect(rig.model.toggleStageFromKeyboard())
        #expect(stage.state == .compact)
    }

    @Test func aPictureStageLeavesTheKeysToTheRealIsland() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while rig.model.step.id != .calendars { rig.model.next() }
        #expect(!rig.model.step.stageIsInteractive)
        #expect(!rig.model.toggleStageFromKeyboard())
        #expect(!rig.model.handleKey(UInt16(kVK_LeftArrow)))
    }

    @Test func showingAStageCancelsAPeekThatWasWaitingOnThePointer() async {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.next()  // Rest the Pointer to Peek
        let stage = rig.model.stageIsland
        stage.setHovering(true)  // schedules a peek in 120 ms
        rig.model.next()  // Open It shows a closed island again, and forgets the pending peek
        try? await Task.sleep(for: .milliseconds(300))
        #expect(stage.state == .compact)
    }

    @Test func theSevenModulesChipsFollowASwipe() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while rig.model.step.id != .modules { rig.model.next() }
        rig.model.stageIsland.perform(.right)
        rig.model.stageChangedTab(rig.model.stageIsland.selectedTab)
        #expect(rig.model.chosenModule == .media)
    }

    @Test func theStagesHitAreaIsTheIslandsSize() {
        let stage = TestSupport.makeViewModel()
        #expect(stage.hitSize == stage.size)
        stage.state = .expanded
        #expect(stage.hitSize == stage.size)
        #expect(stage.hitRect.width == stage.hitSize.width)
    }

    @Test func closeRecordsTheGuideAsSeenAndStartsDeferredMonitors() {
        let rig = makeRig()
        defer { rig.model.stop() }
        #expect(rig.state.needsGuide)
        rig.model.close()
        #expect(!rig.state.needsGuide)
        #expect(rig.ends.list == [.closed])
        #expect(rig.monitorStarts.count == 1)
    }

    @Test func doneOnTheLastStepFinishes() {
        let rig = makeRig()
        defer { rig.model.stop() }
        while !rig.model.flow.isLast { rig.model.advance() }
        #expect(rig.model.primaryTitle == "Done")
        rig.model.advance()
        #expect(rig.ends.list == [.done])
        #expect(!rig.state.needsGuide)
    }

    @Test func openSettingsRequestsTheTourOnce() {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.openSettings()
        #expect(rig.ends.list == [.openSettings])
        #expect(rig.settingsOpened.count == 1)
        #expect(rig.state.tourRequested)
        rig.model.openSettings()
        #expect(rig.settingsOpened.count == 1)
    }

    @Test func openSettingsDoesNotRequestATourAnExistingInstallHasSeen() {
        let rig = makeRig(existing: true, replay: true)
        defer { rig.model.stop() }
        rig.model.openSettings()
        #expect(!rig.state.tourRequested)
    }

    @Test func skipEndsTheGuideThenAsksEveryPendingPermission() async {
        let rig = makeRig(access: StubAccess(states: [.reminders: .allowed]))
        defer { rig.model.stop() }
        await rig.model.skip()
        #expect(rig.ends.list == [.skipped])
        #expect(!rig.state.needsGuide)
        #expect(
            rig.access.requests == [
                .calendars, .bluetooth, .downloads, .camera, .microphone, .screenRecording, .accessibility, .focus,
                .automation,
            ])
        #expect(rig.monitorStarts.count == 1)
    }

    @Test func replayDoesNotAskForAnything() {
        let rig = makeRig(existing: true, replay: true)
        defer { rig.model.stop() }
        while !rig.model.flow.isLast { rig.model.advance() }
        rig.model.advance()
        #expect(rig.access.requests.isEmpty)
        #expect(rig.model.flow.count == 19)
    }

    @Test func endingTwiceDoesNothingTheSecondTime() {
        let rig = makeRig()
        defer { rig.model.stop() }
        rig.model.close()
        rig.model.close()
        rig.model.finish()
        #expect(rig.ends.list == [.closed])
        #expect(rig.monitorStarts.count == 1)
    }
}

struct GuideWindowTests {
    private let size = CGSize(width: 588, height: 640)

    @Test func theRimAndTheHeaderDragTheWindow() {
        #expect(OnboardingPanel.isDragArea(NSPoint(x: 5, y: 300), in: size))  // left rim
        #expect(OnboardingPanel.isDragArea(NSPoint(x: 583, y: 300), in: size))  // right rim
        #expect(OnboardingPanel.isDragArea(NSPoint(x: 300, y: 4), in: size))  // bottom rim
        #expect(OnboardingPanel.isDragArea(NSPoint(x: 300, y: 636), in: size))  // top rim
        #expect(OnboardingPanel.isDragArea(NSPoint(x: 100, y: 612), in: size))  // the header, at the step dots
    }

    @Test func theCloseButtonAndTheContentKeepTheirClicks() {
        // The close button is 28 wide and sits 14 in from the right and from the top.
        #expect(!OnboardingPanel.isDragArea(NSPoint(x: 560, y: 612), in: size))
        #expect(!OnboardingPanel.isDragArea(NSPoint(x: 300, y: 300), in: size))  // the stage and the words
        #expect(!OnboardingPanel.isDragArea(NSPoint(x: 300, y: 28), in: size))  // the footer's buttons
    }
}
