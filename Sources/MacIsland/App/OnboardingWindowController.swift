import AppKit
import SwiftUI

/// The first-run guide's window: floating glass without a resize edge, like a torn-off panel.
final class OnboardingPanel: FloatingGlassPanel {
    override init() {
        super.init()
        styleMask.remove(.resizable)
        // The island peeks on hover through mouse-moved events; with the guide key they must still reach the tracker.
        acceptsMouseMovedEvents = true
    }
}

/// What the guide needs from the app.
struct OnboardingContext {
    let features: IslandFeatures
    /// The real island, which the practice checks watch and the guide gives the keyboard back to.
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
        let model = OnboardingModel(
            state: context.state, settings: context.features.settings, geometry: { island.geometry },
            preview: preview, access: access,
            island: PracticeGoal.Island(
                state: island.state, tab: island.selectedTab, isFileDragActive: island.isFileDragActive),
            replay: replay, startDeferredMonitors: context.startDeferredMonitors,
            openSettings: context.openSettings, onEnd: { [weak self] ending in self?.end(ending) })

        let panel = OnboardingPanel()
        let host = NSHostingView(rootView: OnboardingRoot(model: model, island: island, onFolded: { [weak self] in self?.giveKeyboardBack() }))
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

    /// When the island folds back in, the guide gets the keyboard back (⌃⌥Space gave it to the island), so Return continues
    /// without a click. Only while MacIsland is the active app, so it never takes focus from another one.
    func giveKeyboardBack() {
        guard NSApp.isActive, let panel, !panel.isKeyWindow else { return }
        panel.makeKey()
    }
}
