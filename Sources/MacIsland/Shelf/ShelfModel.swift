import AppKit

/// How long a file stays on the Shelf.
enum ShelfRetention: String, CaseIterable, Identifiable {
    case never, day, week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .day: "After a Day"
        case .week: "After a Week"
        }
    }

    /// Nil keeps files until they are removed by hand.
    var seconds: TimeInterval? {
        switch self {
        case .never: nil
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        }
    }
}

/// Files parked on the island. Only references are kept; files stay where they are.
@MainActor
@Observable
final class ShelfModel {
    private(set) var items: [URL] = []

    @ObservationIgnored private let defaultsKey = "shelf.paths"
    @ObservationIgnored private let addedKey = "shelf.added"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    /// When each file was put on the Shelf, by path. Files from before this was kept count from the first launch after.
    @ObservationIgnored private var added: [String: Date]

    /// `defaults` is the app's own unless a preview or a test gives another, so a sample never touches the real Shelf.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        let paths = defaults.stringArray(forKey: defaultsKey) ?? []
        let existing =
            paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        let stored = defaults.dictionary(forKey: addedKey) as? [String: Date] ?? [:]
        let start = now()
        let dates = Dictionary(
            existing.map { ($0.path, stored[$0.path] ?? start) }, uniquingKeysWith: { first, _ in first })
        items = existing
        added = dates
        if dates != stored { defaults.set(dates, forKey: addedKey) }
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(url) {
            items.append(url)
            added[url.path] = now()
        }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        added[url.path] = nil
        save()
    }

    func addedAt(_ url: URL) -> Date? { added[url.path] }

    /// Takes off what has been here longer than `retention` allows. Only the reference goes; the file stays where it is.
    /// Run on launch and when the Shelf appears, never on a timer. Returns how many it removed.
    @discardableResult
    func sweep(_ retention: ShelfRetention) -> Int {
        guard let limit = retention.seconds else { return 0 }
        let cutoff = now().addingTimeInterval(-limit)
        let expired = items.filter { (added[$0.path] ?? now()) < cutoff }
        guard !expired.isEmpty else { return 0 }
        items.removeAll { expired.contains($0) }
        for url in expired { added[url.path] = nil }
        save()
        return expired.count
    }

    /// Opens the system AirDrop picker for `urls`. Choosing the recipient is the system's step.
    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func clear() {
        items.removeAll()
        added.removeAll()
        save()
    }

    private func save() {
        defaults.set(items.map(\.path), forKey: defaultsKey)
        defaults.set(added, forKey: addedKey)
    }
}
