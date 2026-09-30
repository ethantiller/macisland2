import Foundation

/// Finds new screenshots the moment macOS saves them, through Spotlight's screen-capture flag.
@MainActor
final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?

    private let query = NSMetadataQuery()
    private var observers: [Any] = []
    private var isGathering = true

    var isWatching: Bool { query.isStarted }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        isGathering = true
    }

    func start() {
        guard !query.isStarted else { return }
        query.predicate = NSPredicate(format: "%K == 1", "kMDItemIsScreenCapture")
        query.searchScopes = [NSMetadataQueryUserHomeScope]

        let center = NotificationCenter.default
        observers = [
            // Everything that already exists is the baseline; only later additions are new.
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.isGathering = false }
            },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
                let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
                let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
                MainActor.assumeIsolated { self?.handle(paths) }
            },
        ]
        query.start()
    }

    private func handle(_ paths: [String]) {
        guard !isGathering else { return }
        for path in paths where Self.isVisibleFile(path) {
            onScreenshot?(URL(fileURLWithPath: path))
        }
    }

    /// macOS writes screenshots through a hidden temporary name first.
    nonisolated static func isVisibleFile(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return !name.isEmpty && !name.hasPrefix(".") && FileManager.default.fileExists(atPath: path)
    }
}
