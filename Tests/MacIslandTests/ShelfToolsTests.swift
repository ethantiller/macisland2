import AppKit
import AVFoundation
import PDFKit
import Testing
@testable import MacIsland

struct FileKindTests {
    @Test func kindsComeFromTheExtension() {
        func kind(_ name: String) -> FileKind? { FileKind.of(URL(fileURLWithPath: "/tmp/" + name)) }
        #expect(kind("a.PNG") == .image && kind("a.heic") == .image)
        #expect(kind("a.pdf") == .pdf)
        #expect(kind("a.docx") == .document && kind("a.md") == .document && kind("a.rtfd") == .document)
        #expect(kind("a.MOV") == .video && kind("a.m4v") == .video)
        #expect(kind("a.wav") == .audio && kind("a.mp3") == .audio)
        #expect(kind("a.zip") == nil && kind("folder") == nil)
    }

    @Test func aTargetIsNeverTheFormatTheFileAlreadyIs() {
        func targets(_ name: String) -> [ConversionTarget] { ConversionTarget.targets(for: URL(fileURLWithPath: "/tmp/" + name)) }
        #expect(!targets("a.png").contains(.png) && targets("a.png").contains(.pdf))
        #expect(!targets("a.jpeg").contains(.jpeg) && !targets("a.jpg").contains(.jpeg))
        #expect(!targets("a.docx").contains(.docx) && targets("a.docx").contains(.pdf))
        #expect(targets("a.txt") == [.pdf, .docx, .rtf, .html, .odt])
        #expect(targets("a.md").contains(.html) && targets("a.md").contains(.txt))
        #expect(targets("a.pdf") == [.txt, .png, .jpeg])
        #expect(targets("a.mov") == [.mp4, .m4a, .gif])
        #expect(targets("a.mp4") == [.m4a, .gif])
        #expect(targets("a.wav") == [.m4a])
        #expect(targets("a.zip").isEmpty)
    }
}

struct RecognizedTextTests {
    @Test func readsTopDownThenLeftToRight() {
        let boxes: [(text: String, box: CGRect)] = [
            ("third", CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)),
            ("second-right", CGRect(x: 0.6, y: 0.5, width: 0.2, height: 0.05)),
            ("first", CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.05)),
            ("second-left", CGRect(x: 0.1, y: 0.501, width: 0.3, height: 0.05)),
        ]
        #expect(RecognizedText.ordered(boxes) == ["first", "second-left second-right", "third"])
    }

    @Test func barcodePayloadsFollowTheText() {
        #expect(RecognizedText(lines: ["a", "b"], barcodePayloads: ["https://x.y"]).joined == "a\nb\nhttps://x.y")
    }
}

@MainActor
struct ShelfToolsTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePNG(in directory: URL, name: String = "picture.png", side: Int = 64) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = directory.appendingPathComponent(name)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func makeTools(recognizer: StubRecognizer = StubRecognizer()) -> (FileTools, NSPasteboard, ShelfModel) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let shelf = ShelfModel()
        return (FileTools(shelf: shelf, work: WorkTracker(), recognizer: recognizer, pasteboard: pasteboard), pasteboard, shelf)
    }

    // MARK: Copy Text

    @Test func copyTextPutsTheTextOnThePasteboard() async throws {
        let picture = try makePNG(in: try makeDirectory())
        let (tools, pasteboard, _) = makeTools(recognizer: StubRecognizer(result: RecognizedText(lines: ["Hello", "World"], barcodePayloads: [])))
        var notes: [String] = []
        tools.onNote = { notes.append($0.text) }
        await tools.copyText(from: picture)
        #expect(pasteboard.string(forType: .string) == "Hello\nWorld")
        #expect(notes == ["Copied"])
    }

    @Test func copyTextSaysWhenThereIsNone() async throws {
        let picture = try makePNG(in: try makeDirectory())
        let (tools, pasteboard, _) = makeTools()
        var notes: [String] = []
        tools.onNote = { notes.append($0.text) }
        await tools.copyText(from: picture)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(notes == ["No Text Found"])
    }

    @Test func copyTextFromAClipboardImage() async {
        let (tools, pasteboard, _) = makeTools(recognizer: StubRecognizer(result: RecognizedText(lines: [], barcodePayloads: ["https://a.b"])))
        await tools.copyText(from: NSImage(size: NSSize(width: 8, height: 8), flipped: false) { _ in true })
        #expect(pasteboard.string(forType: .string) == "https://a.b")
    }

    @Test func aPDFWithTextIsReadWithoutTheRecognizer() async throws {
        let directory = try makeDirectory()
        let textFile = directory.appendingPathComponent("note.txt")
        try "Plain words".write(to: textFile, atomically: true, encoding: .utf8)
        let pdf = directory.appendingPathComponent("note.pdf")
        try await Converters.document(at: textFile, to: .pdf, destination: pdf)
        let (tools, pasteboard, _) = makeTools(recognizer: StubRecognizer(result: RecognizedText(lines: ["from OCR"], barcodePayloads: [])))
        await tools.copyText(from: pdf)
        #expect(pasteboard.string(forType: .string)?.contains("Plain words") == true)
        #expect(pasteboard.string(forType: .string)?.contains("from OCR") == false)
    }

    // MARK: Documents

    @Test func aDocumentRoundTripsThroughDocxAndPDFToText() async throws {
        let directory = try makeDirectory()
        let source = directory.appendingPathComponent("letter.txt")
        try "Dear reader,\nthis is a letter.".write(to: source, atomically: true, encoding: .utf8)

        let docx = try await Converters.document(at: source, to: .docx, destination: directory.appendingPathComponent("letter.docx"))
        #expect(FileKind.of(docx) == .document)
        let pdf = try await Converters.document(at: docx, to: .pdf, destination: directory.appendingPathComponent("letter.pdf"))
        #expect(PDFDocument(url: pdf)?.pageCount ?? 0 >= 1)
        let text = try await Converters.convert(pdf, to: .txt, destination: directory.appendingPathComponent("out.txt"))
        let result = try String(contentsOf: text, encoding: .utf8)
        #expect(result.contains("Dear reader") && result.contains("this is a letter"))
    }

    @Test func markdownBecomesHTML() async throws {
        let directory = try makeDirectory()
        let source = directory.appendingPathComponent("readme.md")
        try "# Title\n\nSome **bold** words.\n\n- one\n- two\n".write(to: source, atomically: true, encoding: .utf8)
        let html = try await Converters.document(at: source, to: .html, destination: directory.appendingPathComponent("readme.html"))
        let markup = try String(contentsOf: html, encoding: .utf8)
        #expect(markup.contains("Title") && markup.contains("bold") && markup.contains("one") && markup.contains("two"))
        #expect(!markup.contains("**") && !markup.contains("# Title"))
    }

    @Test func markdownKeepsItsBlocksApart() {
        let text = MarkdownText.render("# Head\n\nBody text\n\n1. first\n2. second").string
        #expect(text == "Head\n\nBody text\n\n1. first\n2. second")
    }

    @Test func aDocumentBecomesRTFAndHTML() async throws {
        let directory = try makeDirectory()
        let source = directory.appendingPathComponent("a.txt")
        try "hello there".write(to: source, atomically: true, encoding: .utf8)
        for target in [ConversionTarget.rtf, .html, .odt] {
            let output = try await Converters.convert(source, to: target, destination: directory.appendingPathComponent("a.\(target.fileExtension)"))
            #expect(FileManager.default.fileExists(atPath: output.path))
        }
        let back = try Converters.readDocument(at: directory.appendingPathComponent("a.rtf"))
        #expect(back.string.contains("hello there"))
    }

    // MARK: PDF

    @Test func aPDFBecomesOneImagePerPage() async throws {
        let directory = try makeDirectory()
        let picture = try makePNG(in: directory)
        let pdf = try Converters.combine([picture, picture], destination: directory.appendingPathComponent("two.pdf"))
        let folder = try await Converters.convert(pdf, to: .png, destination: directory.appendingPathComponent(Converters.outputName(for: pdf, to: .png)))
        #expect(folder.lastPathComponent == "two Pages")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["Page 1.png", "Page 2.png"])
    }

    @Test func combineJoinsImagesAndPDFsInOrder() throws {
        let directory = try makeDirectory()
        let one = try makePNG(in: directory, name: "one.png")
        let two = try makePNG(in: directory, name: "two.png")
        let first = try Converters.combine([one, two], destination: directory.appendingPathComponent("first.pdf"))
        let joined = try Converters.combine([first, one], destination: directory.appendingPathComponent("joined.pdf"))
        #expect(PDFDocument(url: joined)?.pageCount == 3)
        #expect(FileTools.combinable([one, first, directory.appendingPathComponent("a.zip")]) == [one, first])
        #expect(throws: FileToolError.self) { try Converters.combine([], destination: directory.appendingPathComponent("none.pdf")) }
    }

    // MARK: Images

    @Test func resizeKeepsTheFormatAndNeverGrows() throws {
        let directory = try makeDirectory()
        let picture = try makePNG(in: directory, side: 200)
        func size(_ url: URL) -> Int {
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any])[kCGImagePropertyPixelWidth] as! Int
        }
        let half = try Converters.resize(picture, maxPixel: nil, destination: directory.appendingPathComponent("half.png"))
        #expect(size(half) == 100)
        let capped = try Converters.resize(picture, maxPixel: 50, destination: directory.appendingPathComponent("capped.png"))
        #expect(size(capped) == 50)
        let same = try Converters.resize(picture, maxPixel: 1920, destination: directory.appendingPathComponent("same.png"))
        #expect(size(same) == 200)
        #expect(CGImageSourceCreateWithURL(half as CFURL, nil).flatMap(CGImageSourceGetType) as String? == "public.png")
    }

    @Test func compressMakesAJPEG() throws {
        let directory = try makeDirectory()
        let picture = try makePNG(in: directory)
        let output = try Converters.compress(picture, destination: directory.appendingPathComponent("small.jpg"))
        #expect(CGImageSourceCreateWithURL(output as CFURL, nil).flatMap(CGImageSourceGetType) as String? == "public.jpeg")
    }

    // MARK: Audio

    @Test func audioBecomesM4A() async throws {
        let directory = try makeDirectory()
        let wav = directory.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        do {  // the file is only complete once it is released
            let file = try AVAudioFile(forWriting: wav, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
            buffer.frameLength = 4410
            try file.write(from: buffer)
        }

        let output = try await Converters.convert(wav, to: .m4a, destination: directory.appendingPathComponent("tone.m4a"))
        #expect(try await AVURLAsset(url: output).load(.duration).seconds > 0)
    }
}

@MainActor
struct VideoConversionTests {
    /// A one-second, 64 x 48 movie of solid frames.
    private func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32ARGB, nil, &buffer)
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    @Test func aMovieBecomesMP4AndAGIF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let movie = directory.appendingPathComponent("clip.mov")
        try await makeMovie(at: movie)

        let mp4 = try await Converters.convert(movie, to: .mp4, destination: directory.appendingPathComponent("clip.mp4"))
        #expect(try await AVURLAsset(url: mp4).load(.duration).seconds > 0.5)

        let gif = try await Converters.convert(movie, to: .gif, destination: directory.appendingPathComponent("clip.gif"))
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 12)
    }
}
