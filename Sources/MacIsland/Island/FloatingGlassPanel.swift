import AppKit
import SwiftUI

/// A window that floats free of the notch: the command palette, or a module torn off into its own window.
/// Clear, with a shadow, and drawn with Liquid Glass by its content.
final class FloatingGlassPanel: NSPanel {
    enum Style {
        /// Borderless and light, like Spotlight: takes the keyboard without activating the app.
        case palette
        /// A resizable window without chrome, moved by dragging its background.
        case window
    }

    init(style: Style) {
        switch style {
        case .palette:
            super.init(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        case .window:
            super.init(
                contentRect: .zero, styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            titlebarAppearsTransparent = true
            titleVisibility = .hidden
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(button)?.isHidden = true
            }
            isMovableByWindowBackground = true
            level = .floating
        }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    /// Return `true` to swallow a key press before the focused field sees it (arrows, Return, Esc).
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    /// Keeps the top edge where it is when the content changes height, so a palette grows downward.
    var pinnedTop: CGFloat?

    /// Sits above the desktop icons and below every other window, on every Space.
    var keepsOnDesktop = false {
        didSet {
            guard keepsOnDesktop != oldValue else { return }
            if keepsOnDesktop {
                level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            } else {
                level = .floating
                collectionBehavior = []
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let pinnedTop { frame.origin.y = pinnedTop - frame.height }
        super.setFrame(frame, display: flag)
        invalidateShadow()
    }
}

/// True inside a torn-off window or a menu-bar window, where typing must not pin the island open.
private struct FloatingWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isFloatingWindow: Bool {
        get { self[FloatingWindowKey.self] }
        set { self[FloatingWindowKey.self] = newValue }
    }
}
