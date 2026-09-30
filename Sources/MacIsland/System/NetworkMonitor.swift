import Foundation
import Network
import Observation

/// Tracks whether the Mac is online through a Personal Hotspot (an "expensive" path).
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnHotspot = false

    @ObservationIgnored var onHotspotConnect: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var hasInitialPath = false

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let onHotspot = path.status == .satisfied && path.isExpensive
            Task { @MainActor in self?.update(onHotspot: onHotspot) }
        }
        monitor.start(queue: DispatchQueue(label: "MacIsland.network"))
    }

    private func update(onHotspot: Bool) {
        defer {
            isOnHotspot = onHotspot
            hasInitialPath = true
        }
        if hasInitialPath && onHotspot && !isOnHotspot {
            onHotspotConnect?()
        }
    }
}
