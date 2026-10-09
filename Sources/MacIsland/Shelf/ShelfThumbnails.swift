import AppKit
import QuickLookThumbnailing

/// Real previews for the Shelf's files (images, PDFs, movies, documents) from QuickLook Thumbnailing. Generated off the main thread,
/// kept in memory only (never written anywhere), keyed by path and modification date so an edited file is drawn again, and capped.
/// A view asks from `.task(id:)`, so work for an item that scrolls away or leaves the Shelf is cancelled and its answer dropped.
@MainActor
final class ShelfThumbnails {
    static let shared = ShelfThumbnails()

    private let cache = NSCache<NSString, NSImage>()

    init(limit: Int = 64) {
        cache.countLimit = limit
    }

    /// A preview at `size` points, or nil when the system has none (the caller draws the file's icon instead).
    func image(for url: URL, size: CGFloat, scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2) async -> NSImage? {
        // The stat is made off the main thread: a file on a network or iCloud volume can take a while to answer.
        let key = await Task.detached(priority: .userInitiated) { Self.key(for: url, size: size) as String }.value as NSString
        guard !Task.isCancelled else { return nil }
        if let cached = cache.object(forKey: key) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
            !Task.isCancelled
        else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: key)
        return image
    }

    /// The path, the modification date, and the size.
    nonisolated static func key(for url: URL, size: CGFloat) -> NSString {
        // Read fresh: a `URL` caches its resource values, so an edited file would keep its old key and its old preview.
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let stamp = modified.map { String($0.timeIntervalSinceReferenceDate) } ?? "-"
        return "\(url.path)|\(stamp)|\(Int(size))" as NSString
    }
}
