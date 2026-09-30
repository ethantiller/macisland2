import Foundation
import Testing

@testable import MacIsland

@MainActor
struct SettingsTourTests {
    private func stop(_ id: String, _ pane: SettingsPane, target: TourTarget = .shortcut) -> TourStop {
        TourStop(
            id: id, since: 1, pane: pane, target: target, placement: .below, scrollAnchor: nil, preview: nil,
            title: id, copy: id)
    }

    private func makeTour(_ stops: [TourStop], onFinish: @escaping @MainActor () -> Void = {}) -> SettingsTour {
        SettingsTour(stops: stops, onFinish: onFinish)
    }

    // MARK: Stops

    @Test func everyStopHasWordsAndAUniqueId() {
        let ids = TourStop.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for stop in TourStop.all {
            #expect(!stop.title.isEmpty && !stop.copy.isEmpty, stop.id)
        }
    }

    // MARK: Running

    @Test func startNextBackEnd() {
        var finished = 0
        let tour = makeTour([stop("a", .general), stop("b", .general), stop("c", .tabs)], onFinish: { finished += 1 })
        #expect(!tour.isRunning && tour.current == nil)
        tour.start()
        #expect(tour.current?.id == "a")
        tour.back()
        #expect(tour.current?.id == "a")
        tour.next()
        tour.next()
        #expect(tour.current?.id == "c")
        tour.next()
        #expect(!tour.isRunning)
        #expect(finished == 1)
        tour.next()
        tour.end()
        #expect(finished == 1)
    }

    @Test func endingEarlyCallsFinishOnce() {
        var finished = 0
        let tour = makeTour([stop("a", .general), stop("b", .general)], onFinish: { finished += 1 })
        tour.start()
        tour.end()
        tour.end()
        #expect(finished == 1 && !tour.isRunning)
    }

    @Test func anEmptyTourDoesNotStart() {
        let tour = makeTour([])
        tour.start()
        #expect(!tour.isRunning)
    }

    @Test func jumpGoesToThePanesFirstStop() {
        let tour = makeTour([
            stop("a", .general), stop("b", .general), stop("c", .tabs), stop("d", .tabs), stop("e", .home),
        ])
        tour.start()
        tour.jump(to: .tabs)
        #expect(tour.current?.id == "c")
        tour.jump(to: .home)
        #expect(tour.current?.id == "e")
        tour.jump(to: .general)
        #expect(tour.current?.id == "a")
    }

    @Test func jumpingToThePaneTheTourIsAlreadyOnChangesNothing() {
        let tour = makeTour([stop("a", .general), stop("b", .general)])
        tour.start()
        tour.next()
        tour.jump(to: .general)
        #expect(tour.current?.id == "b")
    }

    @Test func jumpingToAPaneWithNoStopChangesNothing() {
        let tour = makeTour([stop("a", .general), stop("b", .tabs)])
        tour.start()
        tour.jump(to: .privacy)
        #expect(tour.current?.id == "a")
    }

    @Test func jumpDoesNothingWhileNotRunning() {
        let tour = makeTour([stop("a", .general), stop("b", .tabs)])
        tour.jump(to: .tabs)
        #expect(!tour.isRunning)
    }

    @Test func finishTourIsRemembered() {
        let suite = "MacIslandTour.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = OnboardingState(defaults: defaults, isExistingInstall: { false })
        #expect(state.needsTour)
        let tour = makeTour([stop("a", .general)], onFinish: { state.finishTour() })
        tour.start()
        tour.next()
        #expect(!state.needsTour)
        #expect(!OnboardingState(defaults: defaults, isExistingInstall: { false }).needsTour)
    }

    // MARK: Anchors

    @Test func anchorsIgnoreUnchangedFrames() {
        let anchors = TourAnchors()
        let frame = CGRect(x: 1, y: 2, width: 3, height: 4)
        anchors.set(.shortcut, frame)
        #expect(anchors.frames[.shortcut] == frame)
        anchors.set(.shortcut, frame)
        #expect(anchors.frames.count == 1)
        anchors.set(.shortcut, nil)
        #expect(anchors.frames.isEmpty)
        anchors.set(.shortcut, nil)
        #expect(anchors.frames.isEmpty)
    }

    // MARK: Placement

    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let size = CGSize(width: 280, height: 100)

    private func place(
        _ target: CGRect, _ preferred: TourStop.Placement, size: CGSize? = nil, bounds: CGRect? = nil
    ) -> CalloutPlacement {
        CalloutPlacement.place(
            target: target, size: size ?? self.size, in: bounds ?? self.bounds, preferred: preferred, gap: 10,
            arrow: CGSize(width: 16, height: 8), edgeInset: 12, cornerRadius: 10)
    }

    @Test func preferredSideWhenItFits() {
        let target = CGRect(x: 300, y: 200, width: 100, height: 30)
        let below = place(target, .below)
        #expect(below.placement == .below)
        #expect(below.frame.minY == target.maxY + 10 + 8)
        #expect(below.frame.midX == target.midX)
        #expect(below.arrowOffset == 140)
        #expect(place(target, .above).placement == .above)
        #expect(place(target, .trailing).placement == .trailing)
        #expect(place(target, .leading).placement == .leading)
    }

    @Test func flipsWhenThereIsNoRoom() {
        let atTheBottom = CGRect(x: 300, y: 540, width: 100, height: 30)
        #expect(place(atTheBottom, .below).placement == .above)
        let atTheTop = CGRect(x: 300, y: 14, width: 100, height: 30)
        #expect(place(atTheTop, .above).placement == .below)
        let atTheRight = CGRect(x: 740, y: 300, width: 50, height: 30)
        #expect(place(atTheRight, .trailing).placement == .leading)
    }

    @Test func staysInsideTheWindow() {
        let inner = bounds.insetBy(dx: 12, dy: 12)
        let targets = [
            CGRect(x: 0, y: 0, width: 50, height: 30), CGRect(x: 750, y: 0, width: 50, height: 30),
            CGRect(x: 0, y: 570, width: 50, height: 30), CGRect(x: 750, y: 570, width: 50, height: 30),
        ]
        for target in targets {
            for side in [TourStop.Placement.above, .below, .leading, .trailing] {
                let placed = place(target, side)
                #expect(inner.contains(placed.frame), "\(target) \(side) \(placed.frame)")
            }
        }
    }

    @Test func arrowAvoidsCorners() {
        // The callout is held inside the window, so a target at its far edge would put the arrow on a rounded corner.
        let right = place(CGRect(x: 780, y: 200, width: 10, height: 30), .below)
        #expect(right.arrowOffset == 280 - 10 - 8)
        let left = place(CGRect(x: 0, y: 200, width: 10, height: 30), .below)
        #expect(left.arrowOffset == 10 + 8)
    }

    @Test func theArrowOfASideCalloutFollowsTheTargetVertically() {
        let target = CGRect(x: 100, y: 300, width: 100, height: 30)
        let placed = place(target, .trailing)
        #expect(placed.placement == .trailing)
        #expect(placed.frame.minX == target.maxX + 10 + 8)
        #expect(placed.arrowOffset == target.midY - placed.frame.minY)
    }

    @Test func mostRoomWhenNothingFits() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 150)
        let placed = place(
            CGRect(x: 20, y: 60, width: 30, height: 30), .below, size: CGSize(width: 280, height: 200), bounds: small)
        #expect(placed.placement == .trailing)
    }

    @Test func visibilityIsWhetherTheCenterIsInThePane() {
        let viewport = CGRect(x: 200, y: 50, width: 600, height: 500)
        #expect(CalloutPlacement.isVisible(CGRect(x: 300, y: 100, width: 100, height: 30), in: viewport))
        #expect(!CalloutPlacement.isVisible(CGRect(x: 300, y: 900, width: 100, height: 30), in: viewport))
        #expect(!CalloutPlacement.isVisible(CGRect(x: 300, y: -40, width: 100, height: 30), in: viewport))
        #expect(CalloutPlacement.isVisible(CGRect(x: 300, y: 900, width: 100, height: 30), in: nil))
    }
}
