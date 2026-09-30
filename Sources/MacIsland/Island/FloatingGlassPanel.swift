import AppKit
import SwiftUI

/// A module torn off the island into a window of its own: resizable, without chrome, moved by dragging its background.
/// Clear, with a shadow, and drawn with Liquid Glass by its content.
class FloatingGlassPanel: NSPanel {
    init(styleMask: NSWindow.StyleMask) {
        super.init(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    /// A torn-off module's window: titled, so it can be resized, with its window buttons hidden.
    convenience init() {
        self.init(styleMask: [.titled, .closable, .resizable, .fullSizeContentView])
    }

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

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
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
