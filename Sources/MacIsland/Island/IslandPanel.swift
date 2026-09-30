import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true

        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = hosting
    }

    /// Esc and the arrow keys while the island has keyboard focus. Return `true` if handled.
    var keyHandler: ((_ keyCode: UInt16) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event.keyCode) != true { super.keyDown(with: event) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a button or slider act immediately instead of just focusing the panel.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
