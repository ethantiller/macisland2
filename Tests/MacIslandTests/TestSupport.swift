import AVFoundation
import AppKit

@testable import MacIsland

/// One place that builds a view model from test doubles, so adding a feature to
/// `IslandFeatures` only changes this file.
@MainActor
enum TestSupport {
    static func makeViewModel(
        bluetooth: StubBluetooth? = nil, camera: StubCamera? = nil,
        screen: StubScreen? = nil, transcriber: StubTranscriber? = nil
    ) -> IslandViewModel {
        // A private suite per view model, so tests running in parallel never see each other's settings.
        let suite = "MacIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shelf = ShelfModel(defaults: defaults, ownedFolder: scratch.appendingPathComponent("Shelf Results"))
        let work = WorkTracker()
        let notes = NotesModel(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let settings = AppSettings(defaults: defaults)
        var geometry = ScreenGeometry.current()
        geometry.notchSize = CGSize(width: 179, height: 32)
        geometry.hasNotch = true
        let viewModel = IslandViewModel(
            features: IslandFeatures(
                nowPlaying: NowPlayingModel(adapter: nil),
                outputs: AudioOutputs(),
                shelf: shelf,
                timer: TimerModel(),
                stopwatch: StopwatchModel(),
                keepAwake: KeepAwake(),
                ringLight: RingLight(),
                micMute: MicrophoneMute(),
                privacy: PrivacyMonitor(),
                transfers: TransferMonitor(),
                network: NetworkMonitor(),
                settings: settings,
                agenda: AgendaMonitor(),
                focus: FocusMode(),
                clipboard: ClipboardHistory(),
                pomodoro: PomodoroModel(defaults: defaults, plan: { settings.pomodoroPlan }),
                work: work,
                weather: WeatherModel(),
                fileTools: FileTools(
                    shelf: shelf, work: work, recognizer: StubRecognizer(),
                    pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)),
                    stagingRoot: scratch.appendingPathComponent("Staging")
                ),
                notes: notes,
                keyboardCleaner: KeyboardCleaner(),
                bluetooth: BluetoothDevices(provider: bluetooth ?? StubBluetooth()),
                mirror: CameraMirror(provider: camera ?? StubCamera()),
                screenRecorder: ScreenRecorder(recorder: screen ?? StubScreen(), shelf: shelf),
                voice: VoiceRecorder(
                    transcriber: transcriber ?? StubTranscriber(), notes: notes, shelf: shelf,
                    folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                ),
                widgets: CustomWidgetValues(fetcher: StubWidgetFetcher()),
                system: SystemModel(sampler: StubSystemSampler()),
                agents: AgentActivity(),
                mixer: AppMixer(
                    settings: settings, listing: StubAppList(), tapper: StubTapper(), defaults: defaults)
            ))
        viewModel.geometry = geometry
        return viewModel
    }
}

/// Returns a fixed reading instead of running Vision.
struct StubRecognizer: TextRecognizing {
    var result = RecognizedText(lines: [], barcodePayloads: [])

    func recognize(_ image: CGImage) async throws -> RecognizedText { result }
}

/// A fixed list of paired devices; connecting works unless told otherwise.
@MainActor
final class StubBluetooth: BluetoothDeviceProviding {
    var devices: [PairedDevice] = []
    var connectSucceeds = true
    private(set) var disconnected: [String] = []

    func pairedAudioDevices() -> [PairedDevice] { devices }

    func connect(_ id: String) async -> Bool {
        guard connectSucceeds, let index = devices.firstIndex(where: { $0.id == id }) else { return false }
        devices[index].isConnected = true
        return true
    }

    func disconnect(_ id: String) {
        disconnected.append(id)
        if let index = devices.firstIndex(where: { $0.id == id }) { devices[index].isConnected = false }
    }
}

/// Answers access questions from a table and records what was asked, so no real permission is ever requested.
@MainActor
final class StubAccess: AccessProviding {
    var states: [AccessKind: PrivacyAccess.State]
    /// What the person would answer to each request.
    var answers: [AccessKind: Bool]
    private(set) var requests: [AccessKind] = []

    init(
        states: [AccessKind: PrivacyAccess.State] = [:], answers: [AccessKind: Bool] = [:]
    ) {
        self.states = Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, states[$0] ?? .notAsked) })
        self.answers = answers
    }

    func state(of kind: AccessKind) -> PrivacyAccess.State { states[kind] ?? .notAsked }

    func request(_ kind: AccessKind) async -> Bool {
        requests.append(kind)
        let granted = answers[kind] ?? true
        states[kind] = granted ? .allowed : .denied
        return granted
    }
}

/// A camera that opens nothing.
@MainActor
final class StubCamera: CameraSessionProviding {
    var access: CameraAccess = .granted
    var allowsWhenAsked = true
    var failsToStart = false
    private(set) var starts = 0
    private(set) var stops = 0

    func requestAccess() async -> Bool {
        access = allowsWhenAsked ? .granted : .denied
        return allowsWhenAsked
    }

    func start() async throws -> AVCaptureSession {
        if failsToStart { throw CameraError.noCamera }
        starts += 1
        return AVCaptureSession()
    }

    func stop() { stops += 1 }
}

/// A screen that records nothing, and hands back a fixed movie.
@MainActor
final class StubScreen: ScreenRecording {
    var hasAccess = true
    var allowsWhenAsked = false
    var failsToStart = false
    let movie = FileManager.default.temporaryDirectory.appendingPathComponent("Screen \(UUID().uuidString).mov")
    private(set) var regions: [CGRect?] = []
    private(set) var stops = 0

    func requestAccess() -> Bool { allowsWhenAsked }

    func start(region: CGRect?, on display: CGDirectDisplayID) async throws {
        if failsToStart { throw FileToolError.failed("No display was found.") }
        regions.append(region)
    }

    func stop() async throws -> URL {
        stops += 1
        return movie
    }
}

/// A microphone that hears a fixed sentence.
@MainActor
final class StubTranscriber: Transcribing {
    var transcript = "Buy milk and call the bank."
    var failsToStart = false
    var level: Float = 0.4
    private(set) var file: URL?
    private(set) var stops = 0

    func start(writingTo file: URL) async throws {
        if failsToStart { throw VoiceError.microphoneDenied }
        self.file = file
        try Data("audio".utf8).write(to: file)
    }

    func stop() async throws -> String {
        stops += 1
        return transcript
    }
}

/// Returns a fixed reading, and counts how often it was asked.
final class StubWidgetFetcher: WidgetValueFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var text = "42"
    var failure: WidgetFetchError?
    /// When set, a fetch waits for it before answering, to hold one in flight.
    var gate: AsyncStream<Void>?

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func value(for source: CustomWidget.Source) async throws -> WidgetValue {
        lock.lock()
        _calls += 1
        lock.unlock()
        if let gate { for await _ in gate { break } }
        if let failure { throw failure }
        return WidgetValue(text: text, detail: nil, fetchedAt: Date())
    }
}

/// Looks at nothing: counts its looks and says what it was told to.
@MainActor
final class StubSystemSampler: SystemSampling {
    var reading = SystemReading(
        cpu: 0.5, memoryUsed: 8 << 30, memoryTotal: 16 << 30, pressure: .normal, thermal: .nominal, battery: nil)
    private(set) var samples = 0
    private(set) var starts = 0
    private(set) var stops = 0

    func start() { starts += 1 }
    func stop() { stops += 1 }

    func sample() -> SystemReading {
        samples += 1
        return reading
    }
}
