import AppKit

/// Drives hover state and click-through. The panel is always sized for the expanded
/// island, so it only accepts mouse events while the cursor is over the visible shape.
@MainActor
final class MouseTracker {
    private let panel: NSPanel
    private let viewModel: IslandViewModel
    private var monitors: [Any] = []
    private var dragPollTimer: Timer?
    private var dragStartedOnIsland = false
    private var dragPasteboardCount = 0
    private var scrolling = ScrollRouting()
    private var dialSettleTask: Task<Void, Never>?

    init(panel: NSPanel, viewModel: IslandViewModel) {
        self.panel = panel
        self.viewModel = viewModel

        let events: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .scrollWheel,
        ]
        // Global monitor sees events going to other apps (panel ignoring the mouse);
        // local monitor sees events delivered to the panel itself.
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: events,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
            })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: events,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            })
        {
            monitors.append(local)
        }
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .scrollWheel {
            handleScroll(event)
            return
        }
        if event.type == .leftMouseDown {
            dragStartedOnIsland = viewModel.hitRect.contains(NSEvent.mouseLocation)
            if viewModel.isPinnedOpen, !dragStartedOnIsland { viewModel.closePinned() }
            dragPasteboardCount = NSPasteboard(name: .drag).changeCount
            startDragPolling()
        }
        update()
    }

    /// Two-finger swipes over the island: down opens, up closes, left and right change tabs. Momentum after the
    /// fingers lift is ignored, so one gesture acts once. Over the timer dial a horizontal gesture scrubs the
    /// dial instead, with its momentum, and a mouse wheel steps a minute (see `ScrollRouting`).
    private func handleScroll(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        guard viewModel.hitRect.contains(location) || scrolling.ownsGesture else { return }
        let sample = ScrollSample(
            dx: event.scrollingDeltaX,
            dy: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            isInverted: event.isDirectionInvertedFromDevice,
            isBegan: event.phase.contains(.began),
            isMomentum: !event.momentumPhase.isEmpty
        )
        let overDial = viewModel.timerDialRect?.contains(location) ?? false
        switch scrolling.route(sample, overDial: overDial) {
        case .scrubDial(let dx):
            viewModel.scrubDial(byFingerDX: dx)
            scheduleDialSettle()
        case .stepDial(let step):
            viewModel.stepDial(step)
        case .swipe(let swipe):
            perform(swipe)
        case nil:
            break
        }
    }

    /// The dial settles on a whole minute once its scroll, and any coasting after it, has gone quiet.
    private func scheduleDialSettle() {
        dialSettleTask?.cancel()
        dialSettleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.viewModel.endDialScrub()
        }
    }

    private func perform(_ swipe: Swipe) {
        guard viewModel.settings.swipesEnabled else { return }
        switch swipe {
        case .down where viewModel.presentation != .expanded:
            viewModel.open()
        case .up where viewModel.presentation == .expanded:
            viewModel.closePinned()
        case .left where viewModel.presentation == .expanded:
            // The strip follows the fingers: swiping left moves toward the tab on the left.
            viewModel.selectAdjacentTab(-1)
        case .right where viewModel.presentation == .expanded:
            viewModel.selectAdjacentTab(1)
        default:
            break
        }
    }

    /// While a file is dragged from another app, that app runs its own drag loop and we
    /// stop receiving move events, so poll the cursor until the button is released.
    private func startDragPolling() {
        dragPollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.update()
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    timer.invalidate()
                    self.dragPollTimer = nil
                    self.dragStartedOnIsland = false
                    self.update()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragPollTimer = timer
    }

    private func update() {
        // A drag that started on the island (the scrubber, a shelf item) keeps it open
        // even if the cursor wanders outside before the button is released.
        let location = NSEvent.mouseLocation
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        let inside = (dragStartedOnIsland && buttonDown) || viewModel.hitRect.contains(location)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        // Only a drag that put file URLs on the drag pasteboard counts; text, links, and windows don't.
        let drag = NSPasteboard(name: .drag)
        let draggingFile =
            buttonDown && !dragStartedOnIsland
            && drag.changeCount != dragPasteboardCount && drag.types?.contains(.fileURL) == true
        viewModel.setFileDragActive(draggingFile)

        let onCompactControl = viewModel.compactControlRect?.contains(location) ?? false
        // While a file is dragged, the island grows to be an easy target but only opens once the
        // file is over it (the drop target opens it), and stays open while the file is on it.
        let canOpen = !draggingFile || viewModel.state != .compact
        viewModel.setHovering(inside && !onCompactControl && canOpen)
    }
}
