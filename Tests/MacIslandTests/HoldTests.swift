import Foundation
import Testing

@testable import MacIsland

/// The island stays open while a menu, Quick Look, a panel, a text field, or Mirror is using it.
@MainActor
struct HoldTests {
    private let outside = CGPoint(x: -10_000, y: -10_000)

    private func openViewModel(camera: StubCamera? = nil) -> IslandViewModel {
        let viewModel = TestSupport.makeViewModel(camera: camera)
        viewModel.pointerLocation = { CGPoint(x: -10_000, y: -10_000) }
        viewModel.open()
        return viewModel
    }

    private func startMirror(_ viewModel: IslandViewModel) async {
        viewModel.startMirror()
        for _ in 0..<50 where viewModel.mirror.session == nil && !viewModel.mirror.isUnavailable && viewModel.mirror.access != .denied {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func holdsAreCountedByName() {
        let viewModel = openViewModel()
        #expect(!viewModel.isHeld)
        viewModel.hold(.menu)
        viewModel.hold(.quickLook)
        #expect(viewModel.isHeld && viewModel.holds == [.menu, .quickLook])
        // Ending one reason never lets go of another.
        viewModel.release(.menu)
        #expect(viewModel.isHeld && viewModel.holds == [.quickLook])
        viewModel.release(.quickLook)
        #expect(!viewModel.isHeld)
        // Releasing what isn't held, or Mirror by name, does nothing.
        viewModel.release(.panel)
        viewModel.hold(.mirror)
        #expect(!viewModel.isHeld)
    }

    @Test func aHoldKeepsTheIslandOpenWhenThePointerLeaves() async {
        let viewModel = openViewModel()
        viewModel.setHovering(true)
        viewModel.hold(.menu)
        viewModel.setHovering(false)
        try? await Task.sleep(for: .milliseconds(450))
        #expect(viewModel.state == .expanded)
    }

    @Test func theCloseStartsWhenTheLastHoldEndsAndThePointerIsAway() async {
        let viewModel = openViewModel()
        viewModel.setHovering(true)
        viewModel.hold(.menu)
        viewModel.hold(.panel)
        viewModel.setHovering(false)
        viewModel.release(.menu)
        try? await Task.sleep(for: .milliseconds(450))
        #expect(viewModel.state == .expanded, "a panel still holds it")
        viewModel.release(.panel)
        #expect(viewModel.state == .expanded, "the delay starts now, not at once")
        for _ in 0..<100 where viewModel.state != .compact {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(viewModel.state == .compact)
    }

    @Test func aHoldAskingToCloseWithThePointerBackDoesNotClose() async {
        let viewModel = openViewModel()
        viewModel.setHovering(true)
        viewModel.hold(.menu)
        viewModel.setHovering(false)
        viewModel.pointerLocation = { viewModel.hitRect.center }
        viewModel.release(.menu)
        try? await Task.sleep(for: .milliseconds(450))
        #expect(viewModel.state == .expanded)
    }

    @Test func aHoldStopsAClickOutsideFromClosingAPinnedIsland() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.toggleFromKeyboard()
        #expect(viewModel.closesOnClickOutside)
        viewModel.hold(.menu)
        #expect(!viewModel.closesOnClickOutside)
        viewModel.release(.menu)
        #expect(viewModel.closesOnClickOutside)
        // Not pinned, nothing to close.
        viewModel.closePinned()
        #expect(!viewModel.closesOnClickOutside)
    }

    @Test func textFocusEndsWithThePointerOrAClose() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.open()
        viewModel.hold(.textFocus)
        #expect(viewModel.isHeld && viewModel.closesOnClickOutside)
        viewModel.setHovering(true)
        #expect(!viewModel.isHeld, "the pointer takes over")

        viewModel.hold(.textFocus)
        viewModel.closePinned()
        #expect(!viewModel.isHeld && viewModel.state == .compact)
    }

    @Test func menuTrackingHoldsUntilTheLastMenuEnds() {
        let viewModel = TestSupport.makeViewModel()
        let observer = MenuHoldObserver(viewModel: viewModel)
        observer.ended()
        #expect(!viewModel.isHeld, "an end with no begin is ignored")
        observer.began()
        observer.began()
        observer.ended()
        #expect(viewModel.holds == [.menu], "a submenu ended; the menu is still open")
        observer.ended()
        #expect(!viewModel.isHeld)
    }

    @Test func quickLookHoldsWhileItIsUp() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.quickLookURL = URL(fileURLWithPath: "/tmp/a.txt")
        #expect(viewModel.holds == [.quickLook])
        viewModel.quickLookURL = nil
        #expect(!viewModel.isHeld)
    }

    @Test func aPanelHoldLastsForTheLengthOfTheCall() async {
        let viewModel = TestSupport.makeViewModel()
        let during = await viewModel.holding(.panel) { viewModel.holds }
        #expect(during == [.panel])
        #expect(!viewModel.isHeld)
    }

    @Test func aBannerDoesNotFoldAHeldIslandItWaitsAsAnAlert() {
        let viewModel = openViewModel()
        viewModel.hold(.menu)
        viewModel.showBanner(
            IslandBanner(systemImage: "bell.fill", tint: Theme.Tint.attention, title: "Battery Low"),
            respectingFocus: false)
        #expect(viewModel.state == .expanded && viewModel.banner == nil)
        #expect(viewModel.alert?.text == "Battery Low" && viewModel.alert?.staysUntilSeen == true)
    }

    // MARK: Mirror

    @Test func mirrorHoldsExactlyAsLongAsTheCameraIsOnAndWorking() async {
        let viewModel = openViewModel()
        #expect(!viewModel.activeHolds.contains(.mirror))
        await startMirror(viewModel)
        #expect(viewModel.mirror.isOn && viewModel.activeHolds.contains(.mirror))
        viewModel.stopMirror()
        #expect(!viewModel.mirror.isOn && !viewModel.isHeld)
    }

    @Test func mirrorIsNotClosedByEscTheShortcutASwipeUpOrAClickOutside() async {
        let viewModel = openViewModel()
        await startMirror(viewModel)
        viewModel.closePinned()
        #expect(viewModel.state == .expanded && viewModel.mirror.isOn)
        viewModel.toggleFromKeyboard()
        #expect(viewModel.state == .expanded && viewModel.mirror.isOn)
        viewModel.perform(.up)
        #expect(viewModel.state == .expanded && viewModel.mirror.isOn)
        #expect(!viewModel.closesOnClickOutside)

        // Leaving with the pointer doesn't fold it either.
        viewModel.setHovering(true)
        viewModel.setHovering(false)
        try? await Task.sleep(for: .milliseconds(450))
        #expect(viewModel.state == .expanded && viewModel.mirror.isOn)

        // Done is the way out, and the island closes normally after it.
        viewModel.stopMirror()
        viewModel.closePinned()
        #expect(viewModel.state == .compact)
    }

    @Test func swipingAndArrowsAreIgnoredWhileMirrorIsOn() async {
        let viewModel = openViewModel()
        await startMirror(viewModel)
        viewModel.perform(.left)
        viewModel.perform(.right)
        viewModel.selectAdjacentTab(1)
        viewModel.selectAdjacentTab(-1)
        #expect(viewModel.selectedTab == .tools && viewModel.mirror.isOn)
    }

    @Test func aBannerWaitsWhileMirrorIsOn() async {
        let viewModel = openViewModel()
        await startMirror(viewModel)
        viewModel.showBanner(
            IslandBanner(systemImage: "bell.fill", tint: Theme.Tint.attention, title: "Meeting"),
            respectingFocus: false)
        #expect(viewModel.state == .expanded && viewModel.mirror.isOn)
        #expect(viewModel.alert?.staysUntilSeen == true)
    }

    @Test func aDeniedOrFailedCameraHoldsNothing() async {
        let denied = StubCamera()
        denied.access = .denied
        let deniedModel = openViewModel(camera: denied)
        await startMirror(deniedModel)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(deniedModel.mirror.isOn && !deniedModel.isHeld)
        deniedModel.closePinned()
        #expect(deniedModel.state == .compact)

        let broken = StubCamera()
        broken.failsToStart = true
        let brokenModel = openViewModel(camera: broken)
        await startMirror(brokenModel)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(brokenModel.mirror.isUnavailable && !brokenModel.isHeld)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
