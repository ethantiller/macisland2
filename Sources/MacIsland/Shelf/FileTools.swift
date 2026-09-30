import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// What a Shelf image can be converted to.
enum ImageFormat: String, CaseIterable, Identifiable {
    case heic = "HEIC"
    case png = "PNG"
    case jpeg = "JPEG"
    case tiff = "TIFF"
    case pdf = "PDF"

    var id: Self { self }

    var type: UTType {
        switch self {
        case .heic: .heic
        case .png: .png
        case .jpeg: .jpeg
        case .tiff: .tiff
        case .pdf: .pdf
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        default: rawValue.lowercased()
        }
    }

    /// HEIC needs hardware support, so ask the system instead of assuming.
    var isAvailable: Bool {
        self == .pdf || (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier)
    }
}

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

/// Zip, unzip, and convert files on the Shelf. The result lands on the Shelf too.
@MainActor
final class FileTools {
    private let shelf: ShelfModel
    private let work: WorkTracker

    /// Called with a short past-tense word ("Zipped") or, on failure, the reason.
    var onDone: ((String) -> Void)?
    var onFail: ((String) -> Void)?

    init(shelf: ShelfModel, work: WorkTracker) {
        self.shelf = shelf
        self.work = work
    }

    func zip(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let destination = Self.uniqueURL(for: Self.zipDestination(for: urls), in: first.deletingLastPathComponent())
        run("Zipping", success: "Zipped") { try Self.zip(urls, to: destination) }
    }

    func unzip(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        run("Unzipping", success: "Unzipped") { try Self.unzip(url, into: directory) }
    }

    func convert(_ url: URL, to format: ImageFormat) {
        let destination = Self.uniqueURL(
            for: url.deletingPathExtension().lastPathComponent + "." + format.fileExtension,
            in: url.deletingLastPathComponent()
        )
        run("Converting", success: "Converted") { try Self.convertImage(at: url, to: format, destination: destination) }
    }

    private func run(_ title: String, success: String, _ job: @escaping @Sendable () throws -> URL) {
        let id = work.begin(title)
        Task {
            let result = await Task.detached { Result { try job() } }.value
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

    /// Images through ImageIO; a PDF is made with PDFKit, one page per image.
    nonisolated static func convertImage(at url: URL, to format: ImageFormat, destination: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw FileToolError.unreadable
        }
        if format == .pdf {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { throw FileToolError.unreadable }
            let document = PDFDocument()
            document.insert(page, at: 0)
            guard document.write(to: destination) else { throw FileToolError.failed("The PDF could not be saved.") }
            return destination
        }
        guard format.isAvailable,
              let output = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw FileToolError.failed("\(format.rawValue) isn’t supported on this Mac.") }
        // Carries over orientation and metadata, and drops nothing but the container.
        CGImageDestinationAddImageFromSource(output, source, 0, nil)
        guard CGImageDestinationFinalize(output) else { throw FileToolError.failed("The image could not be converted.") }
        return destination
    }

    /// The formats offered for an item: images only, and not the one it already is.
    nonisolated static func conversions(for url: URL) -> [ImageFormat] {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return [] }
        return ImageFormat.allCases.filter { $0.isAvailable && $0.type != type }
    }

    nonisolated static func isZip(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .zip) == true
    }
}
