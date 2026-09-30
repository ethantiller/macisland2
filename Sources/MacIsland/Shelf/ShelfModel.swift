import AppKit

/// Files parked on the island. Only references are kept; files stay where they are.
@MainActor
@Observable
final class ShelfModel {
    private(set) var items: [URL] = []

    @ObservationIgnored private let defaultsKey = "shelf.paths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(url) {
            items.append(url)
        }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    /// Opens the system AirDrop picker for `urls`. Choosing the recipient is the system's step.
    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: defaultsKey)
    }
}
