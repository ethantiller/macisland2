import AppKit
import CoreGraphics

/// One window of the window server's list, as far as the full-screen check needs it.
struct WindowSnapshot: Equatable {
    var ownerPID: Int32
    var layer: Int
    /// In the window server's coordinates: the top-left of the main display is the origin.
    var bounds: CGRect
}

enum FullScreenDetector {
    /// Whether the app in front has an ordinary window (layer 0) the size of the whole display, menu bar included. A window that is
    /// only maximized leaves the menu bar showing, so it is not as tall. Public calls only; the private space-listing API is not used.
    static func isFullScreen(windows: [WindowSnapshot], frontmostPID: Int32?, display: CGRect, tolerance: CGFloat = 1) -> Bool {
        guard let frontmostPID else { return false }
        return windows.contains {
            $0.ownerPID == frontmostPID && $0.layer == 0
                && abs($0.bounds.minX - display.minX) <= tolerance && abs($0.bounds.minY - display.minY) <= tolerance
                && abs($0.bounds.width - display.width) <= tolerance && abs($0.bounds.height - display.height) <= tolerance
        }
    }

    /// The windows on screen now, without the desktop's. Owner and bounds need no permission (names do, and are not read).
    static func liveWindows() -> [WindowSnapshot] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return nil }
            return WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds)
        }
    }

    /// The island display's bounds in the window server's coordinates.
    @MainActor
    static func displayBounds(of appKitFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame == appKitFrame }
        if let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }
        return CGDisplayBounds(CGMainDisplayID())
    }
}

/// Tells when the front app goes full screen on the island's display, and when it stops. It listens to two notifications (the space
/// changed, another app came forward) and looks then, so it costs nothing in between; stopped, it listens to nothing.
@MainActor
final class FullScreenWatcher {
    var onChange: ((Bool) -> Void)?
    /// The island display's frame (AppKit coordinates).
    var screenFrame: () -> CGRect = { NSScreen.main?.frame ?? .zero }

    private var observers: [NSObjectProtocol] = []

    var isWatching: Bool { !observers.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.check() }
                })
        }
        check()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
        onChange?(false)
    }

    func check() {
        let on = FullScreenDetector.isFullScreen(
            windows: FullScreenDetector.liveWindows(),
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            display: FullScreenDetector.displayBounds(of: screenFrame()))
        onChange?(on)
    }
}
