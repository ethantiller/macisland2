import CoreGraphics
import Testing
@testable import MacIsland

@MainActor
struct PresentationTests {
    @Test func hoverSwellsThenPeeks() async throws {
        let viewModel = TestSupport.makeViewModel()
        viewModel.setHovering(true)
        #expect(viewModel.isSwelling)
        #expect(viewModel.state == .compact)

        // The dwell is 120 ms; allow for a busy machine rather than sleeping an exact time.
        for _ in 0..<50 where viewModel.state != .peek { try await Task.sleep(for: .milliseconds(20)) }
        #expect(viewModel.state == .peek)
        #expect(!viewModel.isSwelling)
        #expect(viewModel.presentation == .peek)
        #expect(viewModel.size.width == Theme.Metrics.peekWidth)
    }

    @Test func openGivesExpandedAtFullWidth() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.open()
        #expect(viewModel.state == .expanded)
        #expect(viewModel.size.width == Theme.Metrics.expandedWidth)
    }

    @Test func bannerSharesWidthWithPeek() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.showBanner(IslandBanner(systemImage: "bolt", tint: Theme.Tint.neutral, title: "T", detail: "D"))
        #expect(viewModel.presentation == .banner)
        #expect(viewModel.size.width == Theme.Metrics.peekWidth)
    }

    @Test func leavingReturnsToCompact() async throws {
        let viewModel = TestSupport.makeViewModel()
        viewModel.setHovering(true)
        for _ in 0..<50 where viewModel.state != .peek { try await Task.sleep(for: .milliseconds(20)) }
        viewModel.setHovering(false)
        for _ in 0..<50 where viewModel.state != .compact { try await Task.sleep(for: .milliseconds(20)) }
        #expect(viewModel.state == .compact)
    }

    @Test func leavingBeforeTheDwellNeverPeeks() async throws {
        let viewModel = TestSupport.makeViewModel()
        viewModel.setHovering(true)
        viewModel.setHovering(false)
        #expect(!viewModel.isSwelling)
        try await Task.sleep(for: .milliseconds(200))
        #expect(viewModel.state == .compact)
    }

    @Test func dragTargetIsUnchanged() {
        let viewModel = TestSupport.makeViewModel()
        let resting = viewModel.size
        viewModel.setFileDragActive(true)
        #expect(viewModel.showsDragTarget)
        #expect(viewModel.size.height == resting.height + Theme.Metrics.dragTargetHeight)
        #expect(viewModel.size.width == viewModel.geometry.compactSize.width + 2 * Theme.Metrics.dragTargetInset)
    }

    @Test func pillWithoutANotchIsHiddenUntilSomethingIsLive() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.geometry.hasNotch = false
        #expect(viewModel.isPillHidden)
        #expect(viewModel.size == .zero)
        // The hover zone stays.
        #expect(viewModel.hitRect.width > 0)

        viewModel.flash(IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "80%"))
        #expect(!viewModel.isPillHidden)
        #expect(viewModel.size.width > 0)
    }
}

struct SwipeRecognizerTests {
    @Test func swipeDownWithNaturalScrollingIsPositiveDelta() {
        var swipe = SwipeRecognizer()
        #expect(swipe.add(dx: 0, dy: 10, inverted: true, began: true) == nil)
        #expect(swipe.add(dx: 0, dy: 20, inverted: true, began: false) == .down)
    }

    @Test func traditionalScrollingFlipsTheSign() {
        var swipe = SwipeRecognizer()
        #expect(swipe.add(dx: 0, dy: -30, inverted: false, began: true) == .down)
    }

    @Test func horizontalNeedsMoreAndFiresOncePerGesture() {
        var swipe = SwipeRecognizer()
        #expect(swipe.add(dx: -40, dy: 0, inverted: true, began: true) == nil)
        #expect(swipe.add(dx: -30, dy: 0, inverted: true, began: false) == .left)
        #expect(swipe.add(dx: -80, dy: 0, inverted: true, began: false) == nil)
        #expect(swipe.add(dx: 70, dy: 0, inverted: true, began: true) == .right)
    }

    @Test func diagonalDriftDoesNotFire() {
        var swipe = SwipeRecognizer()
        #expect(swipe.add(dx: 30, dy: 30, inverted: true, began: true) == nil)
    }
}
