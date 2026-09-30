import Foundation
import Observation

/// Progress of files arriving in Downloads (AirDrop, Safari, and other apps that publish
/// file progress, the same source Finder uses for its progress bars).
@MainActor
@Observable
final class TransferMonitor {
    struct Transfer: Identifiable, Equatable {
        let id: UUID
        var url: URL
        var fraction: Double

        /// Name without the in-progress suffix Safari adds.
        var displayURL: URL {
            url.pathExtension == "download" ? url.deletingPathExtension() : url
        }
    }

    private(set) var transfers: [Transfer] = []

    @ObservationIgnored var onFinish: ((URL) -> Void)?
    @ObservationIgnored private var subscriber: Any?

    var overallFraction: Double {
        guard !transfers.isEmpty else { return 0 }
        return transfers.map(\.fraction).reduce(0, +) / Double(transfers.count)
    }

    /// Safe to call again: the first-run guide may hold this back on a fresh install, and more than one path can start it.
    func start() {
        guard subscriber == nil,
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return
        }
        // The monitor lives as long as the app, so an unowned capture is safe.
        subscriber = Progress.addSubscriber(forFileURL: downloads) { [unowned self] progress in
            let id = UUID()
            let url = progress.fileURL ?? downloads
            let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in self.update(id: id, url: url, fraction: fraction) }
            }
            return {
                observation.invalidate()
                Task { @MainActor in self.finish(id: id) }
            }
        }
    }

    private func update(id: UUID, url: URL, fraction: Double) {
        if let index = transfers.firstIndex(where: { $0.id == id }) {
            transfers[index].fraction = fraction
        } else {
            transfers.append(Transfer(id: id, url: url, fraction: fraction))
        }
    }

    private func finish(id: UUID) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        let transfer = transfers.remove(at: index)
        if transfer.fraction >= 0.99 {
            onFinish?(transfer.displayURL)
        }
    }
}
