import AppKit

/// Holds the island open (`IslandHold.menu`) while any AppKit menu is tracking. SwiftUI's `.contextMenu`, `Menu`, and `ShareLink` are
/// `NSMenu`s, and a menu draws outside the island, so the pointer going into it is not the pointer leaving the island. One observer
/// for every menu, so no view needs to know about it. Menus nest (a submenu), so it counts.
@MainActor
final class MenuHoldObserver {
    private let viewModel: IslandViewModel
    private var depth = 0
    private var tokens: [NSObjectProtocol] = []

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.began() }
            })
        tokens.append(
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.ended() }
            })
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// A menu began tracking.
    func began() {
        depth += 1
        viewModel.hold(.menu)
    }

    /// A menu ended tracking. The hold goes with the last one; an end with no begin is ignored.
    func ended() {
        depth = max(depth - 1, 0)
        if depth == 0 { viewModel.release(.menu) }
    }
}
