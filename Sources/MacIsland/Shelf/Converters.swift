import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// What a Shelf file is, for the tools that only make sense for some kinds.
enum FileKind {
    case image, document, pdf, video, audio

    private nonisolated static let documentExtensions: Set<String> = [
        "docx", "doc", "rtf", "rtfd", "odt", "txt", "html", "htm", "md", "markdown",
    ]
    private nonisolated static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    private nonisolated static let audioExtensions: Set<String> = ["wav", "aiff", "aif", "mp3", "caf"]

    nonisolated static func of(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if documentExtensions.contains(ext) { return .document }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) { return .image }
        return nil
    }
}

/// What a Shelf file can be converted to.
enum ConversionTarget: String, CaseIterable, Identifiable {
    case heic = "HEIC"
    case png = "PNG"
    case jpeg = "JPEG"
    case tiff = "TIFF"
    case pdf = "PDF"
    case docx = "DOCX"
    case rtf = "RTF"
    case txt = "TXT"
    case html = "HTML"
    case odt = "ODT"
    case mp4 = "MP4"
    case m4a = "M4A"
    case gif = "GIF"

    var id: Self { self }

    var type: UTType {
        switch self {
        case .heic: .heic
        case .png: .png
        case .jpeg: .jpeg
        case .tiff: .tiff
        case .pdf: .pdf
        case .docx: UTType(filenameExtension: "docx") ?? .data
        case .rtf: .rtf
        case .txt: .plainText
        case .html: .html
        case .odt: UTType(filenameExtension: "odt") ?? .data
        case .mp4: .mpeg4Movie
        case .m4a: .mpeg4Audio
        case .gif: .gif
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
        guard self == .heic else { return true }
        return (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier)
    }

    /// The formats offered for a file: only what its kind can become, and never the one it already is.
    nonisolated static func targets(for url: URL) -> [ConversionTarget] {
        guard let kind = FileKind.of(url) else { return [] }
        let ext = url.pathExtension.lowercased()
        let own = UTType(filenameExtension: ext)
        let candidates: [ConversionTarget] =
            switch kind {
            case .image: [.heic, .png, .jpeg, .tiff, .pdf]
            case .document: [.pdf, .docx, .rtf, .txt, .html, .odt]
            case .pdf: [.txt, .png, .jpeg]
            case .video: [.mp4, .m4a, .gif]
            case .audio: [.m4a]
            }
        return candidates.filter { $0.isAvailable && $0.type != own && $0.fileExtension != ext }
    }
}

/// `NSAttributedString` isn't `Sendable`, but a document is only handed between the steps of one conversion.
struct SendableText: @unchecked Sendable {
    let value: NSAttributedString
    init(_ value: NSAttributedString) { self.value = value }
}

/// Every conversion, done with the system's own frameworks.
enum Converters {
    /// The file (or, for PDF to images, the folder) a conversion makes, before it is made unique.
    nonisolated static func outputName(for url: URL, to target: ConversionTarget) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        if FileKind.of(url) == .pdf, target == .png || target == .jpeg { return base + " Pages" }
        return base + "." + target.fileExtension
    }

    static func convert(_ url: URL, to target: ConversionTarget, destination: URL) async throws -> URL {
        switch FileKind.of(url) {
        case .image:
            return try await Task.detached { try image(at: url, to: target, destination: destination) }.value
        case .document:
            return try await document(at: url, to: target, destination: destination)
        case .pdf:
            return try await Task.detached { try pdf(at: url, to: target, destination: destination) }.value
        case .video:
            switch target {
            case .m4a: return try await export(url, preset: AVAssetExportPresetAppleM4A, as: .m4a, to: destination)
            case .gif: return try await gif(from: url, to: destination)
            default: return try await export(url, preset: AVAssetExportPresetHighestQuality, as: .mp4, to: destination)
            }
        case .audio:
            return try await export(url, preset: AVAssetExportPresetAppleM4A, as: .m4a, to: destination)
        case nil:
            throw FileToolError.unreadable
        }
    }

    // MARK: Images

    /// Images through ImageIO; a PDF is made with PDFKit.
    nonisolated static func image(at url: URL, to format: ConversionTarget, destination: URL) throws -> URL {
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
        else { throw FileToolError.failed("\(format.rawValue) isn\u{2019}t supported on this Mac.") }
        // Carries over orientation and metadata, and drops nothing but the container.
        CGImageDestinationAddImageFromSource(output, source, 0, nil)
        guard CGImageDestinationFinalize(output) else { throw FileToolError.failed("The image could not be converted.") }
        return destination
    }

    /// `maxPixel` is the long edge; `nil` halves the image.
    nonisolated static func resize(_ url: URL, maxPixel: Int?, destination: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw FileToolError.unreadable }
        let longEdge = max(width, height)
        let target = min(maxPixel ?? max(longEdge / 2, 1), longEdge)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileToolError.unreadable
        }
        // Keep the format the file already has, unless this Mac can't write it.
        let identifier = CGImageSourceGetType(source) as String?
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        let type = identifier.flatMap { writable.contains($0) ? $0 : nil } ?? UTType.png.identifier
        try write(thumbnail, type: type, quality: nil, to: destination)
        return destination
    }

    /// A JPEG at quality 0.7, flattened onto white so transparency doesn't turn black.
    nonisolated static func compress(_ url: URL, destination: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw FileToolError.unreadable }
        let flattened = flatten(image) ?? image
        try write(flattened, type: UTType.jpeg.identifier, quality: 0.7, to: destination)
        return destination
    }

    private nonisolated static func flatten(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    nonisolated static func write(_ image: CGImage, type: String, quality: Double?, to destination: URL) throws {
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil) else {
            throw FileToolError.failed("The image could not be saved.")
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw FileToolError.failed("The image could not be saved.") }
    }

    /// One page per image, and PDFs contribute their own pages.
    nonisolated static func combine(_ urls: [URL], destination: URL) throws -> URL {
        let combined = PDFDocument()
        for url in urls {
            switch FileKind.of(url) {
            case .pdf:
                guard let document = PDFDocument(url: url) else { throw FileToolError.unreadable }
                for index in 0..<document.pageCount {
                    if let page = document.page(at: index) { combined.insert(page, at: combined.pageCount) }
                }
            case .image:
                guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { throw FileToolError.unreadable }
                combined.insert(page, at: combined.pageCount)
            default:
                continue
            }
        }
        guard combined.pageCount > 0 else { throw FileToolError.failed("There is nothing to combine.") }
        guard combined.write(to: destination) else { throw FileToolError.failed("The PDF could not be saved.") }
        return destination
    }

    // MARK: PDF

    nonisolated static func pdf(at url: URL, to target: ConversionTarget, destination: URL) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw FileToolError.unreadable }
        switch target {
        case .txt:
            do {
                try (document.string ?? "").write(to: destination, atomically: true, encoding: .utf8)
            } catch {
                throw FileToolError.failed(error.localizedDescription)
            }
            return destination
        case .png, .jpeg:
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                throw FileToolError.failed(error.localizedDescription)
            }
            let digits = String(document.pageCount).count
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = render(page, scale: 2) else { continue }
                let name = "Page " + String(format: "%0\(digits)d", index + 1) + "." + target.fileExtension
                try write(image, type: target.type.identifier, quality: target == .jpeg ? 0.9 : nil, to: destination.appendingPathComponent(name))
            }
            return destination
        default:
            throw FileToolError.failed("\(target.rawValue) isn\u{2019}t supported for a PDF.")
        }
    }

    /// A page drawn onto white at `scale` times its size.
    nonisolated static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0, let context = CGContext(
            data: nil, width: Int(box.width * scale), height: Int(box.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.origin.x, y: -box.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: Documents

    /// The way TextEdit's engine opens each kind. Markdown is read as text and laid out by `MarkdownText`.
    private nonisolated static func documentType(forExtension ext: String) -> NSAttributedString.DocumentType? {
        switch ext {
        case "docx": .officeOpenXML
        case "doc": .docFormat
        case "rtf": .rtf
        case "rtfd": .rtfd
        case "odt": .openDocument
        case "html", "htm": .html
        case "txt": .plain
        default: nil
        }
    }

    /// HTML import uses WebKit, which must run on the main actor; everything else can run anywhere.
    nonisolated static func readDocument(at url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw FileToolError.unreadable }
            return MarkdownText.render(text)
        }
        guard let type = documentType(forExtension: ext) else { throw FileToolError.unreadable }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if type == .plain { options[.characterEncoding] = String.Encoding.utf8.rawValue }
        do {
            return try NSAttributedString(url: url, options: options, documentAttributes: nil)
        } catch {
            throw FileToolError.failed("The document could not be read.")
        }
    }

    nonisolated static func writeDocument(_ text: NSAttributedString, as target: ConversionTarget, to destination: URL) throws {
        let range = NSRange(location: 0, length: text.length)
        let data: Data?
        do {
            switch target {
            case .txt: data = text.string.data(using: .utf8)
            case .docx: data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            case .rtf: data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            case .html: data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
            case .odt: data = try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.openDocument])
            default: throw FileToolError.failed("\(target.rawValue) isn\u{2019}t supported for a document.")
            }
            guard let data else { throw FileToolError.failed("The document could not be converted.") }
            try data.write(to: destination)
        } catch let error as FileToolError {
            throw error
        } catch {
            throw FileToolError.failed(error.localizedDescription)
        }
    }

    @MainActor
    static func document(at url: URL, to target: ConversionTarget, destination: URL) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        let text: SendableText
        if ext == "html" || ext == "htm" {
            text = SendableText(try readDocument(at: url))
        } else {
            text = try await Task.detached { SendableText(try readDocument(at: url)) }.value
        }
        if target == .pdf {
            try makePDF(from: text.value, to: destination)
        } else {
            try await Task.detached { try writeDocument(text.value, as: target, to: destination) }.value
        }
        return destination
    }

    /// Lays the text out in an `NSTextView` and prints it to a file, paginated on the default paper.
    @MainActor
    static func makePDF(from text: NSAttributedString, to destination: URL) throws {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        info.leftMargin = 54
        info.rightMargin = 54
        info.topMargin = 54
        info.bottomMargin = 54
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.textContainerInset = .zero
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(text)
        if let container = view.textContainer, let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            view.frame.size.height = max(layout.usedRect(for: container).height, 1)
        }

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: destination.path) else {
            throw FileToolError.failed("The PDF could not be saved.")
        }
    }

    // MARK: Video and audio

    static func export(_ url: URL, preset: String, as type: AVFileType, to destination: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw FileToolError.unreadable }
        do {
            try await session.export(to: destination, as: type)
        } catch {
            throw FileToolError.failed(error.localizedDescription)
        }
        return destination
    }

    /// The first 15 seconds at 12 frames a second, at most 640 px on a side, as a looping GIF.
    static func gif(from url: URL, to destination: URL) async throws -> URL {
        let frameRate = 12.0
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration.isFinite, duration > 0 else { throw FileToolError.unreadable }
        let count = max(1, Int(min(15, duration) * frameRate))
        let times = (0..<count).map { CMTime(seconds: Double($0) / frameRate, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(seconds: 1 / (frameRate * 2), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw FileToolError.failed("The GIF could not be saved.")
        }
        CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / frameRate]] as CFDictionary

        // A frame that can't be read repeats the one before it, so the count still adds up.
        var last: CGImage?
        var added = 0
        for await result in generator.images(for: times) {
            if let image = try? result.image { last = image }
            guard let last else { continue }
            CGImageDestinationAddImage(output, last, frame)
            added += 1
        }
        guard let last else { throw FileToolError.unreadable }
        while added < count {
            CGImageDestinationAddImage(output, last, frame)
            added += 1
        }
        guard CGImageDestinationFinalize(output) else { throw FileToolError.failed("The GIF could not be saved.") }
        return destination
    }
}

/// Markdown laid out as styled text, so it can become a document. `AttributedString` reads the syntax but
/// leaves the block breaks and the fonts to us.
enum MarkdownText {
    nonisolated static func render(_ markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        }
        let result = NSMutableAttributedString()
        var currentBlock: Int?
        var previousWasListItem = false
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            let listItem = components.contains { if case .listItem = $0.kind { true } else { false } }
            if block != currentBlock {
                if currentBlock != nil {
                    result.append(NSAttributedString(string: listItem && previousWasListItem ? "\n" : "\n\n"))
                }
                if let prefix = listPrefix(components) {
                    result.append(NSAttributedString(string: prefix, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
                }
                currentBlock = block
                previousWasListItem = listItem
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font(for: run, components: components)]
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }

    private nonisolated static func listPrefix(_ components: [PresentationIntent.IntentType]) -> String? {
        guard let item = components.first(where: { if case .listItem = $0.kind { true } else { false } }),
            case .listItem(let ordinal) = item.kind
        else { return nil }
        let ordered = components.contains { if case .orderedList = $0.kind { true } else { false } }
        return ordered ? "\(ordinal). " : "\u{2022} "
    }

    private nonisolated static func font(for run: AttributedString.Runs.Run, components: [PresentationIntent.IntentType]) -> NSFont {
        var size: CGFloat = 13
        var bold = false
        for component in components {
            if case .header(let level) = component.kind {
                size = [24, 20, 17, 15, 14, 13][min(max(level, 1), 6) - 1]
                bold = true
            }
        }
        let inline = run.inlinePresentationIntent ?? []
        if inline.contains(.code) || components.contains(where: { if case .codeBlock = $0.kind { true } else { false } }) {
            return NSFont.monospacedSystemFont(ofSize: 12, weight: bold || inline.contains(.stronglyEmphasized) ? .bold : .regular)
        }
        var font = NSFont.systemFont(ofSize: size, weight: bold || inline.contains(.stronglyEmphasized) ? .bold : .regular)
        if inline.contains(.emphasized) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}
