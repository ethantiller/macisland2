import Foundation
import Testing

@testable import MacIsland

@MainActor
struct ChooseActivityTests {
    private func make(featureOn: Bool = true, timer: Bool = true, music: Bool = true) -> IslandViewModel {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.chooseActivity, featureOn)
        if music {
            var state = NowPlayingState()
            state.title = "Midnight City"
            state.isPlaying = true
            viewModel.nowPlaying.apply(state)
        }
        if timer { viewModel.timer.start(minutes: 25) }
        return viewModel
    }

    private func alert() -> IslandAlert {
        IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "64%")
    }

    @Test func aChosenActivityLeadsThePairAndThePeek() {
        let viewModel = make()
        #expect(viewModel.compactPair?.leading == .timer && viewModel.compactPair?.trailing == .media, "the usual order")
        viewModel.chooseActivity(.media)
        #expect(viewModel.compactActivity == .media)
        #expect(viewModel.compactPair?.leading == .media && viewModel.compactPair?.trailing == .timer, "still a pair of two")
        #expect(viewModel.compactActivities.count == 2)
        viewModel.chooseActivity(.timer)
        #expect(viewModel.compactActivity == .timer)
    }

    @Test func bannersAndAlertsStillComeFirst() {
        let viewModel = make()
        viewModel.chooseActivity(.media)
        viewModel.flash(alert(), respectingFocus: false)
        let list = viewModel.compactActivities
        guard case .alert = list[0] else {
            Issue.record("an alert leads")
            return
        }
        #expect(list[1] == .media && list[2] == .timer, "the choice leads what is left")
        #expect(viewModel.choosableActivities == [.media, .timer], "an alert is not a choice")
        viewModel.clearAlert()
        viewModel.showBanner(PreviewSamples.banner(), for: .seconds(86_400), respectingFocus: false)
        if case .banner = viewModel.compactActivity {} else { Issue.record("a banner stands alone") }
        #expect(viewModel.compactActivities.count == 1)
        viewModel.dismissBanner()
    }

    @Test func theChoiceClearsWhenItEnds() {
        let viewModel = make()
        viewModel.chooseActivity(.media)
        viewModel.nowPlaying.apply(NowPlayingState())
        #expect(viewModel.compactActivity == .timer, "nothing to lead")
        // The island folding after the peek is when the choice is forgotten.
        viewModel.state = .peek
        viewModel.state = .compact
        #expect(viewModel.chosenActivityID == nil)
        var state = NowPlayingState()
        state.title = "Again"
        viewModel.nowPlaying.apply(state)
        #expect(viewModel.compactActivity == .timer, "the music comes back in its usual place")
    }

    @Test func aChoiceSurvivesTheIslandFoldingWhileItLasts() {
        let viewModel = make()
        viewModel.chooseActivity(.media)
        viewModel.state = .peek
        viewModel.state = .compact
        #expect(viewModel.compactActivity == .media)
    }

    @Test func noRowWithOneActivityOrWithTheFeatureOff() {
        let one = make(music: false)
        #expect(!one.showsActivityChoice)
        let two = make()
        #expect(two.showsActivityChoice && two.choosableActivities == [.timer, .media])
        let off = make(featureOn: false)
        #expect(!off.showsActivityChoice)
        off.chooseActivity(.media)
        #expect(off.compactActivity == .timer, "a choice does nothing with the feature off")
        let none = make(timer: false, music: false)
        #expect(!none.showsActivityChoice && none.choosableActivities.isEmpty)
    }

    @Test func thePeekHeightIncludesTheRow() {
        let viewModel = make()
        let row = Theme.Metrics.hitTarget + Theme.Metrics.rowSpacing
        #expect(viewModel.peekContentHeight == row + Theme.Metrics.glanceHeight)
        viewModel.chooseActivity(.media)
        #expect(viewModel.peekContentHeight == row + viewModel.mediaContentHeight(peek: true))
        let off = make(featureOn: false)
        #expect(off.peekContentHeight == Theme.Metrics.glanceHeight, "as it was")
    }

    @Test func eachActivityHasAName() {
        #expect(CompactActivity.timer.title == "Timer" && CompactActivity.pomodoro.title == "Pomodoro")
        #expect(CompactActivity.stopwatch.title == "Stopwatch" && CompactActivity.media.title == "Music")
        #expect(CompactActivity.transfer.title == "Download" && CompactActivity.working("Zipping").title == "Zipping")
        #expect(CompactActivity.agent.title == "Agents" && CompactActivity.recording(.voice).title == "Voice Note")
        #expect(CompactActivity.working("a").choiceID == CompactActivity.working("b").choiceID)
    }

    @Test func thePreviewShowsTwoActivitiesAndStopsThemAfter() {
        let live = TestSupport.makeViewModel()
        live.settings.setOn(.chooseActivity, true)
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.show(Feature.chooseActivity.previewContext ?? PreviewContext(), animated: false)
        preview.viewModel.nowPlaying.apply(PreviewSamples.track())
        #expect(preview.viewModel.showsActivityChoice)
        preview.show(PreviewContext(presentation: .compact), animated: false)
        #expect(!preview.viewModel.timer.isActive, "the sample timer is not left running")
        #expect(!live.timer.isActive)
    }
}
