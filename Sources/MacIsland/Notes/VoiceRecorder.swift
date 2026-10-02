import AVFoundation
import AppKit
import Observation
import Speech

/// Records and transcribes speech, behind a protocol so tests never open the microphone.
@MainActor
protocol Transcribing: AnyObject {
    /// Starts the microphone, writing audio to `file`, and transcribing as it goes.
    func start(writingTo file: URL) async throws
    /// Stops, and returns everything that was said.
    func stop() async throws -> String
    /// The input loudness, 0 to 1. Read only while something is showing it.
    var level: Float { get }
}

enum VoiceError: LocalizedError, Equatable {
    case microphoneDenied
    case noSpeechModel

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off."
        case .noSpeechModel: "Speech recognition isn\u{2019}t available for this language."
        }
    }
}

/// A voice note: audio kept in Application Support, its words as a new note, and the audio on the Shelf. Capped at 10 minutes.
@MainActor
@Observable
final class VoiceRecorder {
    nonisolated static let maxDuration: Duration = .seconds(10 * 60)

    private(set) var startedAt: Date?
    var isRecording: Bool { startedAt != nil }
    /// The input loudness while recording.
    var level: Float { transcriber.level }

    @ObservationIgnored var onFail: ((Error) -> Void)?
    /// Called when the note is saved.
    @ObservationIgnored var onSaved: (() -> Void)?

    @ObservationIgnored private let transcriber: Transcribing
    @ObservationIgnored private let notes: NotesModel
    @ObservationIgnored private let shelf: ShelfModel
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let maxDuration: Duration
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private var capTask: Task<Void, Never>?

    init(
        transcriber: Transcribing, notes: NotesModel, shelf: ShelfModel, folder: URL? = nil,
        now: @escaping () -> Date = Date.init, maxDuration: Duration = VoiceRecorder.maxDuration
    ) {
        self.transcriber = transcriber
        self.notes = notes
        self.shelf = shelf
        self.folder = folder ?? Self.defaultFolder
        self.now = now
        self.maxDuration = maxDuration
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The transcriber for this Mac: `SpeechTranscriber` on macOS 26, the older on-device recognizer before it.
    static func systemTranscriber() -> Transcribing {
        if #available(macOS 26, *) { SpeechVoiceTranscriber() } else { RecognizerVoiceTranscriber() }
    }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacIsland", isDirectory: true)
            .appendingPathComponent("Voice Notes", isDirectory: true)
    }

    func start() async {
        guard !isRecording else { return }
        let started = now()
        let destination = FileTools.uniqueURL(for: "Voice Note \(Self.fileStamp(started)).m4a", in: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await transcriber.start(writingTo: destination)
        } catch {
            onFail?(error)
            return
        }
        file = destination
        startedAt = started
        capTask = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: maxDuration)
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    func stop() async {
        guard let started = startedAt, let audio = file else { return }
        capTask?.cancel()
        capTask = nil
        startedAt = nil
        file = nil
        let transcript: String
        do {
            transcript = try await transcriber.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            onFail?(error)
            return
        }
        let title = Self.title(for: started)
        let note = notes.addNote()
        notes.setBody(title + "\n\n" + (transcript.isEmpty ? "No speech was recognized." : transcript), ofNote: note.id)
        notes.save()
        shelf.add([audio])
        onSaved?()
    }

    /// "Voice Note, 3:45 PM"
    nonisolated static func title(for date: Date) -> String {
        "Voice Note, " + date.formatted(date: .omitted, time: .shortened)
    }

    private nonisolated static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        return formatter.string(from: date)
    }
}

/// The loudness of the last buffer, written from the audio thread and read from the main one.
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Float = 0

    var value: Float { lock.withLock { current } }

    func update(from buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let level = min(1, (sum / Float(buffer.frameLength)).squareRoot() * 6)
        lock.withLock { current = level }
    }

    func reset() { lock.withLock { current = 0 } }
}

/// The `.m4a` a voice note is kept in: AAC at the microphone's own sample rate and channels.
private func voiceAudioFile(writingTo file: URL, matching micFormat: AVAudioFormat) throws -> AVAudioFile {
    try AVAudioFile(
        forWriting: file,
        settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: micFormat.sampleRate,
            AVNumberOfChannelsKey: micFormat.channelCount,
            AVEncoderBitRateKey: 64_000,
        ])
}

/// The microphone, written to an .m4a and read by the on-device `SpeechTranscriber` (macOS 26).
@available(macOS 26, *)
@MainActor
final class SpeechVoiceTranscriber: Transcribing {
    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var words: Task<String, Error>?

    var level: Float { meter.value }

    func start(writingTo file: URL) async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceError.microphoneDenied }

        let transcriber = SpeechTranscriber(locale: Locale.current, preset: .transcription)
        // The language model is downloaded once, then runs on this Mac.
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.noSpeechModel
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (sequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: sequence)
        self.analyzer = analyzer
        input = builder
        words = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters) + " "
            }
            return text
        }

        let inputNode = engine.inputNode
        let micFormat = inputNode.outputFormat(forBus: 0)
        let audio = try voiceAudioFile(writingTo: file, matching: micFormat)
        let converter = AVAudioConverter(from: micFormat, to: format)
        let meter = meter
        meter.reset()
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            try? audio.write(from: buffer)
            meter.update(from: buffer)
            guard let converter else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / micFormat.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var failure: NSError?
            converter.convert(to: converted, error: &failure) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if failure == nil { builder.yield(AnalyzerInput(buffer: converted)) }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() async throws -> String {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        meter.reset()
        input?.finish()
        input = nil
        defer {
            analyzer = nil
            words = nil
        }
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        return try await words?.value ?? ""
    }
}

/// The microphone, written to an .m4a and read by `SFSpeechRecognizer`, on this Mac only (macOS 15, before `SpeechTranscriber`).
@MainActor
final class RecognizerVoiceTranscriber: Transcribing {
    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var words: Task<String, Error>?

    var level: Float { meter.value }

    func start(writingTo file: URL) async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceError.microphoneDenied }
        // Audio must never go to Apple's servers, so a language without an on-device model can't be used.
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.supportsOnDeviceRecognition else {
            throw VoiceError.noSpeechModel
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.shouldReportPartialResults = false
        self.request = request
        words = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                var finished = false
                task = recognizer.recognitionTask(with: request) { result, error in
                    guard !finished else { return }
                    if let result, result.isFinal {
                        finished = true
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    } else if let error {
                        finished = true
                        // "No speech detected" is an empty note, not a failure.
                        let quiet = (error as NSError).domain == "kAFAssistantErrorDomain"
                            && [1110, 203].contains((error as NSError).code)
                        if quiet { continuation.resume(returning: "") } else { continuation.resume(throwing: error) }
                    }
                }
            }
        }

        let inputNode = engine.inputNode
        let micFormat = inputNode.outputFormat(forBus: 0)
        let audio = try voiceAudioFile(writingTo: file, matching: micFormat)
        let meter = meter
        meter.reset()
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            try? audio.write(from: buffer)
            meter.update(from: buffer)
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() async throws -> String {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        meter.reset()
        request?.endAudio()
        defer {
            request = nil
            task = nil
            words = nil
        }
        return try await words?.value ?? ""
    }
}
