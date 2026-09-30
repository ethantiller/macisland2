import AppKit
import Observation
import PDFKit
import UniformTypeIdentifiers

enum FileToolError: LocalizedError {
    case unreadable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file could not be read."
        case .failed(let reason): reason
        }
    }
}

/// What a job that makes a file has made, waiting in a staging folder for the person to say where it goes.
struct ShelfResult: Identifiable, Equatable {
    let id = UUID()
    /// What was done, past tense ("Zipped").
    let verb: String
    /// The new file or folder, inside its own staging folder.
    let staged: URL
    /// The Shelf entries it was made from, which Replace swaps for it.
    let sources: [URL]

    var name: String { staged.lastPathComponent }
    /// The staging folder that holds only this result.
    var slot: URL { staged.deletingLastPathComponent() }
}

/// Zip, unzip, convert, and otherwise work on files on the Shelf. A job that makes a file writes it to a staging folder in the
/// temporary directory, so nothing lands anywhere until the person chooses: **Add to Shelf**, **Replace** the original's entry,
/// or **Save to Folder**. A result that is never chosen stays pending, and is thrown away when it is discarded or the app quits.
@MainActor
@Observable
final class FileTools {
    /// Copy Text reads at most this many PDF pages by image; pages with text of their own are free.
    static let ocrPageLimit = 10

    @ObservationIgnored private let shelf: ShelfModel
    @ObservationIgnored private let work: WorkTracker
    @ObservationIgnored private let recognizer: TextRecognizing
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let stagingRoot: URL

    /// Results waiting for the person to choose where they go, oldest first. The Shelf shows the first.
    private(set) var pending: [ShelfResult] = []

    /// Called with a short past-tense word ("Saved") or, on failure, the reason.
    @ObservationIgnored var onDone: ((String) -> Void)?
    @ObservationIgnored var onFail: ((String) -> Void)?
    /// Called with a neutral note ("Copied", "No Text Found").
    @ObservationIgnored var onNote: ((IslandAlert) -> Void)?
    /// A result is ready and waiting for a choice.
    @ObservationIgnored var onResult: ((ShelfResult) -> Void)?
    /// Asks where to save, and returns nil if the person cancels. Tests replace it; the real one is the system save panel.
    @ObservationIgnored var chooseDestination: @MainActor (_ suggestedName: String) async -> URL? = FileTools.presentSavePanel

    init(
        shelf: ShelfModel, work: WorkTracker, recognizer: TextRecognizing = VisionTextRecognizer(),
        pasteboard: NSPasteboard = .general, stagingRoot: URL? = nil
    ) {
        self.shelf = shelf
        self.work = work
        self.recognizer = recognizer
        self.pasteboard = pasteboard
        self.stagingRoot =
            stagingRoot
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("MacIsland Results", isDirectory: true)
    }

    func zip(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let slot = newSlot()
        let destination = slot.appendingPathComponent(Self.zipDestination(for: urls))
        runBlocking("Zipping", success: "Zipped", sources: urls, slot: slot) { try Self.zip(urls, to: destination) }
    }

    func unzip(_ url: URL) {
        let slot = newSlot()
        runBlocking("Unzipping", success: "Unzipped", sources: [url], slot: slot) { try Self.unzip(url, into: slot) }
    }

    func convert(_ url: URL, to target: ConversionTarget) {
        let slot = newSlot()
        let destination = slot.appendingPathComponent(Converters.outputName(for: url, to: target))
        run("Converting", success: "Converted", sources: [url], slot: slot) {
            try await Converters.convert(url, to: target, destination: destination)
        }
    }

    /// The images and PDFs among `urls` become one PDF, "Combined.pdf", beside the first.
    /// The images and PDFs among `urls`, which Combine into PDF joins.
    nonisolated static func combinable(_ urls: [URL]) -> [URL] {
        urls.filter { [.image, .pdf].contains(FileKind.of($0)) }
    }

    func combinePDF(_ urls: [URL]) {
        let pages = Self.combinable(urls)
        guard !pages.isEmpty else { return }
        let slot = newSlot()
        let destination = slot.appendingPathComponent("Combined.pdf")
        runBlocking("Combining", success: "Combined", sources: pages, slot: slot) {
            try Converters.combine(pages, destination: destination)
        }
    }

    /// `maxPixel` is the long edge in pixels; `nil` halves the image.
    func resize(_ url: URL, maxPixel: Int?) {
        let suffix = maxPixel.map { "\($0) px" } ?? "50%"
        let ext = url.pathExtension
        let slot = newSlot()
        let destination = slot.appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + " " + suffix + (ext.isEmpty ? "" : "." + ext))
        runBlocking("Resizing", success: "Resized", sources: [url], slot: slot) {
            try Converters.resize(url, maxPixel: maxPixel, destination: destination)
        }
    }

    func compress(_ url: URL) {
        let slot = newSlot()
        let destination = slot.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " Compressed.jpg")
        runBlocking("Compressing", success: "Compressed", sources: [url], slot: slot) {
            try Converters.compress(url, destination: destination)
        }
    }

    // MARK: Copy Text

    /// Reads the text (and QR codes) in an image or PDF and puts it on the pasteboard.
    func copyText(from url: URL) async {
        let id = work.begin("Reading Text")
        defer { work.end(id) }
        do {
            switch FileKind.of(url) {
            case .image:
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw FileToolError.unreadable }
                finishCopy(try await recognizer.recognize(image).joined)
            case .pdf:
                finishCopy(try await pdfText(at: url))
            default:
                throw FileToolError.unreadable
            }
        } catch {
            onFail?(error.localizedDescription)
        }
    }

    func copyText(from image: NSImage) async {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            onFail?(FileToolError.unreadable.localizedDescription)
            return
        }
        let id = work.begin("Reading Text")
        defer { work.end(id) }
        do {
            finishCopy(try await recognizer.recognize(cgImage).joined)
        } catch {
            onFail?(error.localizedDescription)
        }
    }

    /// A PDF's own text first; only pages that have none are read as images, up to `ocrPageLimit`.
    private func pdfText(at url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else { throw FileToolError.unreadable }
        var pages: [String] = []
        var scanned = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let own = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !own.isEmpty {
                pages.append(own)
            } else if scanned < Self.ocrPageLimit, let image = Converters.render(page, scale: 2) {
                scanned += 1
                let found = try await recognizer.recognize(image).joined
                if !found.isEmpty { pages.append(found) }
            }
        }
        return pages.joined(separator: "\n\n")
    }

    private func finishCopy(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onNote?(IslandAlert(systemImage: "text.viewfinder", tint: Theme.Tint.neutral, text: "No Text Found"))
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        onNote?(IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"))
    }

    /// A fresh staging folder for one job: the job writes inside it, and it goes away with the result.
    private func newSlot() -> URL {
        let slot = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        return slot
    }

    private func run(
        _ title: String, success: String, sources: [URL], slot: URL, _ job: @escaping @Sendable () async throws -> URL
    ) {
        let id = work.begin(title)
        Task {
            let outcome: Result<URL, Error>
            do { outcome = .success(try await job()) } catch { outcome = .failure(error) }
            work.end(id)
            switch outcome {
            case .success(let url):
                let result = ShelfResult(verb: success, staged: url, sources: sources)
                pending.append(result)
                onResult?(result)
            case .failure(let error):
                try? FileManager.default.removeItem(at: slot)
                onFail?(error.localizedDescription)
            }
        }
    }

    /// Runs blocking work off the main thread.
    private func runBlocking(
        _ title: String, success: String, sources: [URL], slot: URL, _ job: @escaping @Sendable () throws -> URL
    ) {
        run(title, success: success, sources: sources, slot: slot) { try await Task.detached { try job() }.value }
    }

    // MARK: Where a result goes

    /// **Add to Shelf**: the result moves into the folder MacIsland owns and its entry goes on the Shelf.
    @discardableResult
    func addToShelf(_ result: ShelfResult) -> Bool {
        guard let url = adopt(result) else { return false }
        shelf.add([url])
        return true
    }

    /// **Replace**: the result takes the place of the entries it was made from. The originals are not touched on disk.
    @discardableResult
    func replaceInShelf(_ result: ShelfResult) -> Bool {
        guard let url = adopt(result) else { return false }
        shelf.replace(result.sources, with: url)
        return true
    }

    /// **Save to Folder**: asks where, and moves the result there. Cancelling the panel leaves the result waiting. Returns whether
    /// it was saved.
    @discardableResult
    func saveToFolder(_ result: ShelfResult) async -> Bool {
        guard pending.contains(result), let destination = await chooseDestination(result.name) else { return false }
        do {
            // The panel has already asked about replacing a file that is there.
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: result.staged)
            } else {
                try FileManager.default.moveItem(at: result.staged, to: destination)
            }
        } catch {
            onFail?(error.localizedDescription)
            return false
        }
        finish(result)
        onDone?("Saved")
        return true
    }

    /// Throws a result away: its staging folder goes and nothing is left anywhere.
    func discard(_ result: ShelfResult) {
        guard pending.contains(result) else { return }
        finish(result)
    }

    /// Removes every staging folder, for launch and quit. Nothing pending survives either.
    func cleanUpStaging() {
        pending.removeAll()
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    private func adopt(_ result: ShelfResult) -> URL? {
        guard pending.contains(result) else { return nil }
        do {
            try FileManager.default.createDirectory(at: shelf.ownedFolder, withIntermediateDirectories: true)
            let destination = Self.uniqueURL(for: result.name, in: shelf.ownedFolder)
            try FileManager.default.moveItem(at: result.staged, to: destination)
            finish(result)
            return destination
        } catch {
            onFail?(error.localizedDescription)
            return nil
        }
    }

    /// Takes a result off the waiting list and removes what is left of its staging folder.
    private func finish(_ result: ShelfResult) {
        pending.removeAll { $0 == result }
        try? FileManager.default.removeItem(at: result.slot)
    }

    /// The system save panel, in Finder's usual way.
    @MainActor static func presentSavePanel(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        NSApp.activate()
        let response = await panel.begin()
        return response == .OK ? panel.url : nil
    }

    // MARK: Work (off the main thread)

    /// One item is zipped under its own name; several go into "Archive.zip".
    nonisolated static func zipDestination(for urls: [URL]) -> String {
        urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "Archive.zip"
    }

    /// `name`, or `name 2`, `name 3`... in `directory`, whichever doesn't exist yet.
    nonisolated static func uniqueURL(for name: String, in directory: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            number += 1
        }
        return candidate
    }

    /// `keepParent` is for folders: the archive then opens to the folder itself. On a lone file it would
    /// embed the folder the file happens to be in, so files are zipped bare.
    nonisolated static func zipArguments(_ sources: [URL], to destination: URL, keepParent: Bool) -> [String] {
        ["-c", "-k", "--sequesterRsrc"] + (keepParent ? ["--keepParent"] : []) + sources.map(\.path) + [
            destination.path
        ]
    }

    nonisolated static func unzipArguments(_ archive: URL, into folder: URL) -> [String] {
        ["-x", "-k", archive.path, folder.path]
    }

    /// One folder or file is zipped under its own name. Several are copied (a clone on APFS, so it is
    /// quick) into a folder named for the archive first, so they open together.
    nonisolated static func zip(_ sources: [URL], to destination: URL) throws -> URL {
        if sources.count == 1 {
            let isFolder = (try? sources[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            try ditto(zipArguments(sources, to: destination, keepParent: isFolder))
            return destination
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let staging = scratch.appendingPathComponent(destination.deletingPathExtension().lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for source in sources {
                try FileManager.default.copyItem(at: source, to: uniqueURL(for: source.lastPathComponent, in: staging))
            }
        } catch {
            throw FileToolError.failed(error.localizedDescription)
        }
        try ditto(zipArguments([staging], to: destination, keepParent: true))
        return destination
    }

    /// Like Finder: a lone item is placed beside the archive as it is; several go into a folder named
    /// for the archive.
    nonisolated static func unzip(_ archive: URL, into directory: URL) throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try ditto(unzipArguments(archive, into: scratch))
        let contents =
            ((try? FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != "__MACOSX" }
        guard !contents.isEmpty else { throw FileToolError.failed("The archive is empty.") }
        do {
            if contents.count == 1 {
                let destination = uniqueURL(for: contents[0].lastPathComponent, in: directory)
                try FileManager.default.moveItem(at: contents[0], to: destination)
                return destination
            }
            let folder = uniqueURL(for: archive.deletingPathExtension().lastPathComponent, in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for item in contents {
                try FileManager.default.moveItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent))
            }
            return folder
        } catch {
            throw FileToolError.failed(error.localizedDescription)
        }
    }

    private nonisolated static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw FileToolError.failed(error.localizedDescription)
        }
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw FileToolError.failed(message?.isEmpty == false ? message! : "ditto failed.")
        }
    }

    nonisolated static func isZip(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .zip) == true
    }
}
