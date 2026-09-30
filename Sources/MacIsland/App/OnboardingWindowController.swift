import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The first-run guide's window: floating glass like a torn-off panel, but borderless: no title bar, so nothing of the window's own
/// sits over the top of the guide (its ⊗ is there), and no resize edge.
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
    let access: AccessProviding
    /// Starts what a fresh install held back until the guide ended.
    let startDeferredMonitors: () -> Void
    /// Starts the headphones monitor alone, when Bluetooth is allowed in the guide.
    let startAccessoryMonitor: () -> Void
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
    /// The app is activated first: an accessory app's window takes no keys, and the system prompts stay behind, until it is.
    func show(replay: Bool) {
        NSApp.activate()
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let context else { return }

        let preview = IslandPreviewModel(live: context.features)
        preview.allowsMenuBar = true
        let access = AccessModel(
            provider: context.access, settings: context.features.settings,
            onBluetoothAllowed: context.startAccessoryMonitor)
        let island = context.island
        // The stage island is the stage's own, which starts at the real island's screen and notch.
        preview.viewModel.geometry = island.geometry
        let model = OnboardingModel(
            state: context.state, settings: context.features.settings, geometry: { island.geometry },
            preview: preview, access: access, replay: replay,
            startDeferredMonitors: context.startDeferredMonitors, openSettings: context.openSettings,
            onEnd: { [weak self] ending in self?.end(ending) })

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
    }

    /// Closing any other way (a menu's Close, ⌘W) counts as the ⊗: seen, and gone.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model?.close()
        return false
    }

    /// The open shortcut pressed while the guide is up: it opens or closes the island in the guide, not the real one, and brings the
    /// guide forward so Esc and the arrows reach it. False when there is no guide, or this step's stage is a picture: the real island
    /// answers then, as usual.
    func handleOpenShortcut() -> Bool {
        guard let panel, let model, model.toggleStageFromKeyboard() else { return false }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        return true
    }
}
