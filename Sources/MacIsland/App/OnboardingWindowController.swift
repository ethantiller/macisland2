import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The first-run guide's window: floating glass like a torn-off panel, but borderless: no title bar, so nothing of the window's own
/// sits over the top of the guide, and no resize edge. It has no way to close: only the guide's Done ends it.
final class OnboardingPanel: FloatingGlassPanel {
    /// Esc, ←, and → go to the island in the guide's window. Returns whether the key was taken.
    var keyHandler: ((_ keyCode: UInt16) -> Bool)?

    init() {
        super.init(styleMask: [.borderless])
        // The stage island peeks on hover through mouse-moved events.
        acceptsMouseMovedEvents = true
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event.keyCode) != true { super.keyDown(with: event) }
    }

    /// Pressing the rim or the header starts a window drag. AppKit does the drag (`performDrag`), so it does not depend on what
    /// SwiftUI makes of the press: neither `isMovableByWindowBackground` nor a `WindowDragGesture` moved this window (found by hand).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let size = contentView?.bounds.size,
            Self.isDragArea(event.locationInWindow, in: size)
        {
            performDrag(with: event)
            return
        }
        super.sendEvent(event)
    }

    /// Where a press drags the window: the glass's rim on every side, and the header row (the step dots). Nothing but the dots sits
    /// there. `point` is in window coordinates, which start at the bottom left.
    static func isDragArea(_ point: NSPoint, in size: CGSize) -> Bool {
        let rim = Theme.Metrics.floatPadding
        let fromTop = size.height - point.y
        let fromRight = size.width - point.x
        if point.x < rim || fromRight < rim || point.y < rim || fromTop < rim { return true }
        return fromTop < rim + Theme.Metrics.hitTarget
    }

    /// Esc is the stage island's. Left alone it reached the panel's own cancel action, which closed the guide (found by hand); the
    /// guide ends only by its own buttons.
    override func cancelOperation(_ sender: Any?) {
        _ = keyHandler?(UInt16(kVK_Escape))
    }
}

/// What the guide needs from the app.
struct OnboardingContext {
    let features: IslandFeatures
    /// The real island: the guide reads its screen and notch, and leaves it alone.
    let island: IslandViewModel
    let state: OnboardingState
    /// The one model Settings → Privacy asks through too, so a grant anywhere counts everywhere.
    let access: AccessModel
    /// The guide ended: the app opens the island and starts what waited for it.
    let guideEnded: () -> Void
    let openSettings: () -> Void
}

/// Shows the first-run guide. Shaped like `SettingsWindowController`: made when first shown, gone when closed, so the stage's
/// preview stops with it.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    /// Set by the app at launch.
    var context: OnboardingContext?
    private var panel: OnboardingPanel?
    private var model: OnboardingModel?

    var isOpen: Bool { panel != nil }

    /// Opens the guide, or brings it forward. `replay` shows every step; otherwise it shows what this install hasn't seen.
    /// `permissionsOnly` shows just the permissions that aren't allowed (one was turned off after the guide was done).
    /// The app is activated first: an accessory app's window takes no keys, and the system prompts stay behind, until it is.
    func show(replay: Bool, permissionsOnly: Bool = false) {
        NSApp.activate()
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let context else { return }

        let preview = IslandPreviewModel(live: context.features)
        preview.allowsMenuBar = true
        let island = context.island
        // The stage island is the stage's own, which starts at the real island's screen and notch.
        preview.viewModel.geometry = island.geometry
        let model = OnboardingModel(
            state: context.state, settings: context.features.settings, geometry: { island.geometry },
            preview: preview, access: context.access, replay: replay, permissionsOnly: permissionsOnly,
            openSettings: context.openSettings, onEnd: { [weak self] ending in self?.end(ending) })

        let panel = OnboardingPanel()
        panel.keyHandler = { [weak self] keyCode in self?.model?.handleKey(keyCode) ?? false }
        // The first click acts, even when the guide isn't the window in front (it floats over other apps).
        let host = FirstMouseHostingView(rootView: OnboardingRoot(model: model))
        host.sizingOptions = []
        panel.contentView = host
        // The whole guide is one size: its content never changes height between steps.
        panel.setContentSize(host.fittingSize)
        panel.setFrameOrigin(Self.origin(for: panel.frame.size, geometry: island.geometry))
        panel.delegate = self
        self.panel = panel
        self.model = model
        panel.makeKeyAndOrderFront(nil)
    }

    /// The middle of the island's screen, in the part the menu bar and the Dock leave free. While the person practises on the real
    /// island, it opens over the top of the guide (it is the higher window); the guide can be dragged out of the way.
    static func origin(for size: CGSize, geometry: ScreenGeometry) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame == geometry.screenFrame } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? geometry.screenFrame
        // A window taller than the screen keeps its footer (Back, Continue) on it.
        return NSPoint(x: visible.midX - size.width / 2, y: max(visible.midY - size.height / 2, visible.minY))
    }

    /// The guide has ended: fade it out, then let go of it.
    private func end(_ ending: GuideEnding) {
        guard let panel else { return }
        let model = model
        let guideEnded = context?.guideEnded
        self.panel = nil
        self.model = nil
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Theme.Motion.reduceMotion ? 0.1 : 0.16
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                MainActor.assumeIsolated {
                    panel.delegate = nil
                    panel.close()
                    model?.stop()
                }
            })
        guideEnded?()
    }

    /// The guide ends only by Done: ⌘W and every other way of closing the window do nothing.
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    /// The open shortcut pressed while the guide is up: it opens or closes the island in the guide, not the real one, and brings the
    /// guide forward so Esc and the arrows reach it. False when there is no guide, or this step's stage is a picture: the real island
    /// answers then, as usual.
    func handleOpenShortcut() -> Bool {
        HotkeyLog.logger.info(
            "open shortcut: panel=\(self.panel != nil) model=\(self.model != nil) step=\(self.model?.step.id.rawValue ?? "-") interactive=\(self.model?.step.stageIsInteractive ?? false) stage=\(String(describing: self.model?.stageIsland.state))"
        )
        guard let panel, let model, model.toggleStageFromKeyboard() else { return false }
        HotkeyLog.logger.info("open shortcut: stage is now \(String(describing: model.stageIsland.state))")
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        return true
    }
}
