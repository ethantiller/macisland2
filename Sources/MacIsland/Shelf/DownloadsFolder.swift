import Foundation
import Observation

/// One file in Downloads, or one that is still arriving.
struct DownloadItem: Identifiable, Equatable {
    /// Where the file is now (a partial file's own path, until it finishes).
    let url: URL
    /// The name to show: a partial file without its suffix.
    let name: String
    let isArriving: Bool
    let added: Date

    var id: URL { url }
}

enum DownloadsScan {
    /// What browsers call a file they are still writing.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part"]
    static let limit = 20

    static func isPartial(_ url: URL) -> Bool { partialExtensions.contains(url.pathExtension.lowercased()) }

    /// The newest `limit` items of a folder by when they were added to it, hidden files skipped. Only the folder's own entries are
    /// read, with the two keys needed: nothing is walked, so a very large Downloads costs one directory listing.
    static func newest(in folder: URL, limit: Int = limit, dateAdded: (URL) -> Date = addedDate) -> [DownloadItem]? {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.addedToDirectoryDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles])
        else { return nil }
        let items = entries.map { url -> DownloadItem in
            let added = dateAdded(url)
            let partial = isPartial(url)
            return DownloadItem(
                url: url, name: partial ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent,
                isArriving: partial, added: added)
        }
        return Array(items.sorted { $0.added > $1.added }.prefix(limit))
    }

    /// When a file came to its folder; the modification date if the file system keeps no such date.
    static func addedDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
        return values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
    }

    /// How far along an arriving file is, from the transfers the system reports, matched by name.
    static func fraction(of item: DownloadItem, in transfers: [TransferMonitor.Transfer]) -> Double? {
        guard item.isArriving else { return nil }
        return transfers.first { $0.displayURL.lastPathComponent == item.name }?.fraction
    }
}

/// The recent files in Downloads and the ones still arriving, for the Shelf's Downloads mode. The folder is listed when the mode shows
/// and watched (one file-system source on the folder) only while it does; hidden, nothing is open and nothing runs.
@MainActor
@Observable
final class DownloadsFolder {
    private(set) var items: [DownloadItem] = []
    /// False when the folder could not be listed (Downloads is not allowed), so the mode can say so.
    private(set) var canRead = true
    private(set) var isWatching = false

    @ObservationIgnored let folder: URL
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// How long after a change the folder is listed again, so a download writing many times is one listing.
    @ObservationIgnored var settleDelay: Duration = .milliseconds(300)

    init(folder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
    {
        self.folder = folder
    }

    func reload() {
        if let found = DownloadsScan.newest(in: folder) {
            if found != items { items = found }
            if !canRead { canRead = true }
        } else {
            if !items.isEmpty { items = [] }
            if canRead { canRead = false }
        }
    }

    /// Lists the folder now and again whenever it changes.
    func start() {
        reload()
        guard source == nil else { return }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        isWatching = true
    }

    func stop() {
        source?.cancel()
        source = nil
        pending?.cancel()
        pending = nil
        isWatching = false
    }

    private func changed() {
        pending?.cancel()
        let delay = settleDelay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
