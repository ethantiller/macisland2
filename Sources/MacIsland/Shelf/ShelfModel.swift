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

/// Files parked on the island. Only references are kept; files stay where they are. The one exception is a result the person
/// chose to Add to the Shelf (Zip, Convert, and so on): it lives in `ownedFolder`, a folder MacIsland keeps, and when its entry
/// leaves the Shelf that file goes to the Trash. A file anywhere else is never touched.
@MainActor
@Observable
final class ShelfModel {
    private(set) var items: [URL] = []

    @ObservationIgnored private let defaultsKey = "shelf.paths"
    @ObservationIgnored private let addedKey = "shelf.added"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    /// Where "Add to the Shelf" puts a result, and the only place a removed entry's file is trashed from.
    @ObservationIgnored let ownedFolder: URL
    @ObservationIgnored private let trash: (URL) -> Void
    /// When each file was put on the Shelf, by path. Files from before this was kept count from the first launch after.
    @ObservationIgnored private var added: [String: Date]

    /// `defaults` is the app's own unless a preview or a test gives another, so a sample never touches the real Shelf.
    init(
        defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
        ownedFolder: URL = ShelfModel.defaultOwnedFolder,
        trash: @escaping (URL) -> Void = { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.defaults = defaults
        self.now = now
        self.ownedFolder = ownedFolder
        self.trash = trash
        let paths = defaults.stringArray(forKey: defaultsKey) ?? []
        // Looking for a file in Desktop, Documents, or Downloads makes macOS ask for that folder, so those are taken on trust here and
        // checked when the Shelf is shown (`verify()`): nothing prompts at launch.
        let existing =
            paths
            .filter { Self.isInProtectedFolder($0) || FileManager.default.fileExists(atPath: $0) }
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

    /// Whether `path` is inside Desktop, Documents, or Downloads, where looking for a file can show a system prompt.
    nonisolated static func isInProtectedFolder(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["Desktop", "Documents", "Downloads"].contains { path.hasPrefix(home + "/" + $0 + "/") }
    }

    /// Takes off what is no longer there. Run when the Shelf appears, which is a use, and so a fine moment for a folder prompt.
    @discardableResult
    func verify() -> Int {
        let gone = items.filter { !FileManager.default.fileExists(atPath: $0.path) }
        guard !gone.isEmpty else { return 0 }
        items.removeAll { gone.contains($0) }
        for url in gone { added[url.path] = nil }
        save()
        return gone.count
    }

    /// `~/Library/Application Support/MacIsland/Shelf Results`.
    nonisolated static var defaultOwnedFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacIsland", isDirectory: true)
            .appendingPathComponent("Shelf Results", isDirectory: true)
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        added[url.path] = nil
        save()
        trashIfOwned(url)
    }

    /// Puts `new` where the first of `old` was, and takes `old` off. Only entries change: no file in `old` is deleted, except a
    /// result MacIsland made and owns, which goes to the Trash like any entry that leaves.
    func replace(_ old: [URL], with new: URL) {
        guard new.isFileURL else { return }
        let index = old.compactMap { items.firstIndex(of: $0) }.min()
        let removed = items.filter { old.contains($0) }
        items.removeAll { old.contains($0) }
        for url in removed { added[url.path] = nil }
        if !items.contains(new) {
            items.insert(new, at: min(index ?? items.count, items.count))
            added[new.path] = now()
        }
        save()
        removed.forEach(trashIfOwned)
    }

    /// Whether `url` is inside the folder MacIsland owns.
    func isOwned(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(ownedFolder.standardizedFileURL.path + "/")
    }

    private func trashIfOwned(_ url: URL) {
        if isOwned(url) { trash(url) }
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
        expired.forEach(trashIfOwned)
        return expired.count
    }

    /// Opens the system AirDrop picker for `urls`. Choosing the recipient is the system's step.
    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func clear() {
        let removed = items
        items.removeAll()
        added.removeAll()
        save()
        removed.forEach(trashIfOwned)
    }

    private func save() {
        defaults.set(items.map(\.path), forKey: defaultsKey)
        defaults.set(added, forKey: addedKey)
    }
}
