import AppKit
import CoreGraphics
import Testing

@testable import MacIsland

struct DialScrubberTests {
    @Test func dragFollowsTranslationNotPosition() {
        // Dragging left pulls higher minutes under the marker: 40 pt at 8 pt a minute is 5 minutes.
        #expect(DialScrubber.position(anchor: 25, translation: -40) == 30)
        // Forty 1-pt events end where one 40-pt event does: the position is a function of the translation.
        var position = 25.0
        for step in 1...40 { position = DialScrubber.position(anchor: 25, translation: -CGFloat(step)) }
        #expect(position == 30)
    }

    @Test func holdingStillNeverChangesTheValue() {
        let first = DialScrubber.resolve(DialScrubber.position(anchor: 42, translation: 16))
        let again = DialScrubber.resolve(DialScrubber.position(anchor: 42, translation: 16))
        #expect(first == again)
        #expect(DialScrubber.snap(first.clamped) == 40)
    }

    @Test func tapPicksTheTickUnderThePointer() {
        #expect(DialScrubber.minute(atX: 236 + 24, markerX: 236, position: 25) == 28)
        #expect(DialScrubber.minute(atX: 236 - 24, markerX: 236, position: 25) == 22)
        #expect(DialScrubber.minute(atX: 236, markerX: 236, position: 25) == 25)
    }

    @Test func visibleRangeFollowsThePositionOnly() {
        #expect(DialScrubber.visibleRange(position: 100, width: 472) == 71...129)
        #expect(DialScrubber.visibleRange(position: 1, width: 472) == 1...30)
        #expect(DialScrubber.visibleRange(position: 1440, width: 472).upperBound == 1440)
    }

    @Test func rubberBandsPastOneAndStopsAt1440() {
        let low = DialScrubber.resolve(-30)
        #expect(low.clamped == 1)
        #expect(low.display < 1)
        #expect(low.overscroll > 0 && low.overscroll < Theme.Metrics.dialRubberBand)

        let high = DialScrubber.resolve(5000)
        #expect(high.clamped == 1440)
        #expect(high.display > 1440)
        #expect(high.overscroll > 0 && high.overscroll < Theme.Metrics.dialRubberBand)

        let inside = DialScrubber.resolve(30)
        #expect(inside.overscroll == 0 && inside.display == 30)
    }

    @Test func snapRoundsToTheNearestMinute() {
        #expect(DialScrubber.snap(42.4) == 42)
        #expect(DialScrubber.snap(42.6) == 43)
        #expect(DialScrubber.snap(-3) == 1)
        #expect(DialScrubber.snap(9000) == 1440)
    }
}

struct ScrollRoutingTests {
    private func trackpad(_ dx: CGFloat, _ dy: CGFloat, began: Bool = false, momentum: Bool = false) -> ScrollSample {
        // Natural scrolling, so the deltas are the finger movement.
        ScrollSample(dx: dx, dy: dy, isPrecise: true, isInverted: true, isBegan: began, isMomentum: momentum)
    }

    @Test func horizontalOverTheDialScrubsIt() {
        var routing = ScrollRouting()
        #expect(routing.route(trackpad(2, 0, began: true), overDial: true) == nil)
        // The axis locks at 4 pt, and nothing before the lock is lost.
        #expect(routing.route(trackpad(3, 0), overDial: true) == .scrubDial(5))
        #expect(routing.route(trackpad(-10, 1), overDial: true) == .scrubDial(-10))
        #expect(routing.ownsGesture)
    }

    @Test func momentumCoastsOnlyForTheDial() {
        var routing = ScrollRouting()
        _ = routing.route(trackpad(6, 0, began: true), overDial: true)
        #expect(routing.route(trackpad(5, 0, momentum: true), overDial: true) == .scrubDial(5))

        var elsewhere = ScrollRouting()
        _ = elsewhere.route(trackpad(70, 0, began: true), overDial: false)
        #expect(elsewhere.route(trackpad(5, 0, momentum: true), overDial: false) == nil)
    }

    @Test func verticalOverTheDialIsTheUsualSwipe() {
        var routing = ScrollRouting()
        // Fingers moving up: with natural scrolling the deltas are negative.
        #expect(routing.route(trackpad(0, -30, began: true), overDial: true) == .swipe(.up))
        #expect(!routing.ownsGesture)
    }

    @Test func horizontalElsewhereChangesTabs() {
        var routing = ScrollRouting()
        #expect(routing.route(trackpad(-70, 0, began: true), overDial: false) == .swipe(.left))
        #expect(!routing.ownsGesture)
    }

    @Test func aScrollerOwnsItsAxisIncludingMomentum() {
        var routing = ScrollRouting()
        #expect(routing.route(trackpad(2, 0, began: true), overDial: false, scrollerAxis: .horizontal) == nil)
        #expect(routing.route(trackpad(3, 0), overDial: false, scrollerAxis: .horizontal) == nil)
        #expect(routing.ownsGesture)
        #expect(routing.route(trackpad(8, 0, momentum: true), overDial: false, scrollerAxis: .horizontal) == nil)
    }

    @Test func aScrollerDoesNotOwnTheOtherAxis() {
        var routing = ScrollRouting()
        #expect(routing.route(trackpad(0, -30, began: true), overDial: false, scrollerAxis: .horizontal) == .swipe(.up))
        #expect(!routing.ownsGesture)
    }

    @Test func verticalScrollerOwnsItsAxisIncludingMomentum() {
        var routing = ScrollRouting()
        #expect(routing.route(trackpad(0, -3, began: true), overDial: false, scrollerAxis: .vertical) == nil)
        #expect(routing.route(trackpad(0, -4), overDial: false, scrollerAxis: .vertical) == nil)
        #expect(routing.ownsGesture)
        #expect(routing.route(trackpad(0, -8, momentum: true), overDial: false, scrollerAxis: .vertical) == nil)
    }

    @Test func noScrollerLeavesExistingSwipeRoutingUnchanged() {
        var routing = ScrollRouting()
        #expect(routing.route(trackpad(-70, 0, began: true), overDial: false) == .swipe(.left))
        #expect(!routing.ownsGesture)
    }

    @Test func aWheelOverTheDialStepsAMinute() {
        var routing = ScrollRouting()
        let notch = ScrollSample(
            dx: 0, dy: 1, isPrecise: false, isInverted: false, isBegan: false, isMomentum: false)
        // With natural scrolling off, a positive delta is the wheel rolled up: it adds.
        #expect(routing.route(notch, overDial: true) == .stepDial(1))
        var down = notch
        down.dy = -1
        #expect(routing.route(down, overDial: true) == .stepDial(-1))
        #expect(routing.route(notch, overDial: false) == nil)
    }

    @Test func theAxisLocksAfterFourPoints() {
        var lock = AxisLock()
        #expect(!lock.add(dx: 3, dy: 0).justLocked)
        let result = lock.add(dx: 0, dy: 5)
        #expect(result.justLocked && result.locked == .vertical)
        // Once locked, later movement in the other direction doesn't change it.
        #expect(lock.add(dx: 50, dy: 0).locked == .vertical)
    }
}

@MainActor
struct DialViewModelTests {
    private func settingATimer() -> IslandViewModel {
        let viewModel = TestSupport.makeViewModel()
        viewModel.dialHaptic = { _ in }
        viewModel.state = .expanded
        viewModel.selectedTab = .clock
        return viewModel
    }

    @Test func scrollAreasAreRegisteredAndRemovedByScreenFrame() {
        let viewModel = TestSupport.makeViewModel()
        let id = UUID()
        let frame = CGRect(x: 20, y: 30, width: 100, height: 40)
        #expect(viewModel.scrollAxis(at: CGPoint(x: 30, y: 40)) == nil)

        viewModel.updateScrollArea(id, frame: frame, axis: .horizontal)
        #expect(viewModel.scrollAxis(at: CGPoint(x: 30, y: 40)) == .horizontal)
        #expect(viewModel.scrollAxis(at: CGPoint(x: 200, y: 40)) == nil)

        viewModel.updateScrollArea(id, frame: nil, axis: .horizontal)
        #expect(viewModel.scrollAxis(at: CGPoint(x: 30, y: 40)) == nil)
    }

    @Test func islandHitTestingIncludesItsShape() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.state = .expanded
        let rect = viewModel.hitRect
        #expect(viewModel.isOverIsland(CGPoint(x: rect.midX, y: rect.midY)))
        #expect(!viewModel.isOverIsland(CGPoint(x: rect.maxX + 100, y: rect.midY)))
    }

    @Test func timerDialRectOnlyWhileSettingATimer() throws {
        let viewModel = settingATimer()
        let rect = try #require(viewModel.timerDialRect)
        #expect(viewModel.hitRect.contains(rect.insetBy(dx: 1, dy: 1)))
        #expect(rect.height == Theme.Metrics.timerDial + Theme.Metrics.rowSpacing)

        viewModel.timer.start(minutes: 5)
        #expect(viewModel.timerDialRect == nil)
        viewModel.timer.reset()

        viewModel.selectedTab = .home
        #expect(viewModel.timerDialRect == nil)
        viewModel.selectedTab = .clock
        viewModel.state = .peek
        #expect(viewModel.timerDialRect == nil)
    }

    @Test func scrubbingTheDialNeverChangesTab() {
        let viewModel = settingATimer()
        viewModel.scrubDial(byFingerDX: -80)
        viewModel.endDialScrub()
        #expect(viewModel.timer.durationMinutes == 15)
        #expect(viewModel.selectedTab == .clock)
        #expect(viewModel.dialPosition == nil)
    }

    @Test func aDragMovesTheRulerOneToOne() {
        let viewModel = settingATimer()
        viewModel.beginDialScrub()
        // Many events with the same cumulative translation change nothing more.
        for _ in 0..<10 { viewModel.scrubDial(translation: -40) }
        #expect(viewModel.timer.durationMinutes == 10)
        viewModel.scrubDial(translation: -44)
        #expect(viewModel.dialPosition == 10.5)
        viewModel.endDialScrub()
        #expect(viewModel.dialPosition == nil)
    }

    @Test func theRulerStretchesPastOneAndStopsAtTheEnds() {
        let viewModel = settingATimer()
        var taps: [NSHapticFeedbackManager.FeedbackPattern] = []
        viewModel.dialHaptic = { taps.append($0) }
        viewModel.scrubDial(byFingerDX: 8 * 100)
        #expect(viewModel.timer.durationMinutes == 1)
        #expect(viewModel.dialOverscroll > 0 && viewModel.dialOverscroll < Theme.Metrics.dialRubberBand)
        #expect(taps.filter { $0 == .generic }.count == 1)
        viewModel.endDialScrub()
        #expect(viewModel.dialOverscroll == 0)

        viewModel.scrubDial(byFingerDX: -8 * 5000)
        #expect(viewModel.timer.durationMinutes == 1440)
        viewModel.endDialScrub()
    }

    @Test func aWheelStepsAMinuteAndStopsAtTheEnds() {
        let viewModel = settingATimer()
        viewModel.stepDial(1)
        #expect(viewModel.timer.durationMinutes == 6)
        viewModel.timer.setDuration(minutes: 1)
        viewModel.stepDial(-1)
        #expect(viewModel.timer.durationMinutes == 1)
    }

    @Test func aTapGlidesToThatMinute() {
        let viewModel = settingATimer()
        viewModel.setDial(to: 28)
        #expect(viewModel.timer.durationMinutes == 28)
    }
}
