import AppKit
import SwiftUI

/// The Settings window, made here instead of by SwiftUI's `Settings` scene. That window comes without a resize edge and keeps a title
/// strip the panes can't use, and both have to be ours. It is made when first opened and gone when closed (so the preview stops with it),
/// and it remembers its size and place.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    /// Set by the app at launch.
    var features: IslandFeatures?
    private var window: NSWindow?

    private static let frameName = "MacIslandSettings"

    var isOpen: Bool { window != nil }

    /// Opens the window, or brings it forward. The island is a panel over other apps, so the app is activated first.
    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let features else { return }
        let host = NSHostingView(rootView: SettingsView(settings: features.settings, features: features))
        // SwiftUI says how small the window may get (from the view's minimum size) and nothing else about its size: a window that
        // followed the content's ideal size would fight every drag of its edge.
        host.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentView = host
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
        // Its view goes with it, so the preview stops.
        closing.contentView = nil
    }
}
