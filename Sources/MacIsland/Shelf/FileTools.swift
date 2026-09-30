import AppKit
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

/// Zip, unzip, convert, and otherwise work on files on the Shelf. The result lands on the Shelf too.
@MainActor
final class FileTools {
    /// Copy Text reads at most this many PDF pages by image; pages with text of their own are free.
    static let ocrPageLimit = 10

    private let shelf: ShelfModel
    private let work: WorkTracker
    private let recognizer: TextRecognizing
    private let pasteboard: NSPasteboard

    /// Called with a short past-tense word ("Zipped") or, on failure, the reason.
    var onDone: ((String) -> Void)?
    var onFail: ((String) -> Void)?
    /// Called with a neutral note ("Copied", "No Text Found").
    var onNote: ((IslandAlert) -> Void)?

    init(
        shelf: ShelfModel, work: WorkTracker, recognizer: TextRecognizing = VisionTextRecognizer(),
        pasteboard: NSPasteboard = .general
    ) {
        self.shelf = shelf
        self.work = work
        self.recognizer = recognizer
        self.pasteboard = pasteboard
    }

    func zip(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let destination = Self.uniqueURL(for: Self.zipDestination(for: urls), in: first.deletingLastPathComponent())
        runBlocking("Zipping", success: "Zipped") { try Self.zip(urls, to: destination) }
    }

    func unzip(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        runBlocking("Unzipping", success: "Unzipped") { try Self.unzip(url, into: directory) }
    }

    func convert(_ url: URL, to target: ConversionTarget) {
        let destination = Self.uniqueURL(for: Converters.outputName(for: url, to: target), in: url.deletingLastPathComponent())
        run("Converting", success: "Converted") { try await Converters.convert(url, to: target, destination: destination) }
    }

    /// The images and PDFs among `urls` become one PDF, "Combined.pdf", beside the first.
    /// The images and PDFs among `urls`, which Combine into PDF joins.
    nonisolated static func combinable(_ urls: [URL]) -> [URL] {
        urls.filter { [.image, .pdf].contains(FileKind.of($0)) }
    }

    func combinePDF(_ urls: [URL]) {
        let pages = Self.combinable(urls)
        guard let first = pages.first else { return }
        let destination = Self.uniqueURL(for: "Combined.pdf", in: first.deletingLastPathComponent())
        runBlocking("Combining", success: "Combined") { try Converters.combine(pages, destination: destination) }
    }

    /// `maxPixel` is the long edge in pixels; `nil` halves the image.
    func resize(_ url: URL, maxPixel: Int?) {
        let suffix = maxPixel.map { "\($0) px" } ?? "50%"
        let ext = url.pathExtension
        let destination = Self.uniqueURL(
            for: url.deletingPathExtension().lastPathComponent + " " + suffix + (ext.isEmpty ? "" : "." + ext),
            in: url.deletingLastPathComponent()
        )
        runBlocking("Resizing", success: "Resized") { try Converters.resize(url, maxPixel: maxPixel, destination: destination) }
    }

    func compress(_ url: URL) {
        let destination = Self.uniqueURL(
            for: url.deletingPathExtension().lastPathComponent + " Compressed.jpg", in: url.deletingLastPathComponent()
        )
        runBlocking("Compressing", success: "Compressed") { try Converters.compress(url, destination: destination) }
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

    private func run(_ title: String, success: String, _ job: @escaping @Sendable () async throws -> URL) {
        let id = work.begin(title)
        Task {
            let result: Result<URL, Error>
            do { result = .success(try await job()) } catch { result = .failure(error) }
            work.end(id)
            switch result {
            case .success(let url):
                shelf.add([url])
                onDone?(success)
            case .failure(let error):
                onFail?(error.localizedDescription)
            }
        }
    }

    /// Runs blocking work off the main thread.
    private func runBlocking(_ title: String, success: String, _ job: @escaping @Sendable () throws -> URL) {
        run(title, success: success) { try await Task.detached { try job() }.value }
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
        ["-c", "-k", "--sequesterRsrc"] + (keepParent ? ["--keepParent"] : []) + sources.map(\.path) + [destination.path]
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
        let contents = ((try? FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)) ?? [])
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
