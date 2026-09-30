import AppKit
@testable import MacIsland

/// One place that builds a view model from test doubles, so adding a feature to
/// `IslandFeatures` only changes this file.
@MainActor
enum TestSupport {
    static func makeViewModel(rates: ExchangeRates? = nil, bluetooth: StubBluetooth? = nil) -> IslandViewModel {
        UserDefaults(suiteName: "MacIslandTests")!.removePersistentDomain(forName: "MacIslandTests")
        let shelf = ShelfModel()
        let work = WorkTracker()
        var geometry = ScreenGeometry.current()
        geometry.notchSize = CGSize(width: 179, height: 32)
        geometry.hasNotch = true
        let viewModel = IslandViewModel(features: IslandFeatures(
            nowPlaying: NowPlayingModel(adapter: nil),
            outputs: AudioOutputs(),
            shelf: shelf,
            timer: TimerModel(),
            stopwatch: StopwatchModel(),
            keepAwake: KeepAwake(),
            lowPower: LowPowerMode(),
            ringLight: RingLight(),
            micMute: MicrophoneMute(),
            privacy: PrivacyMonitor(),
            transfers: TransferMonitor(),
            network: NetworkMonitor(),
            settings: AppSettings(defaults: UserDefaults(suiteName: "MacIslandTests")!),
            agenda: AgendaMonitor(),
            focus: FocusMode(),
            clipboard: ClipboardHistory(),
            batteries: DeviceBatteries(),
            pomodoro: PomodoroModel(defaults: UserDefaults(suiteName: "MacIslandTests")!),
            work: work,
            weather: WeatherModel(),
            fileTools: FileTools(
                shelf: shelf, work: work, recognizer: StubRecognizer(),
                pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            ),
            notes: NotesModel(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keyboardCleaner: KeyboardCleaner(),
            launch: LaunchModel(appDirectories: []),
            stats: SystemStats(),
            rates: rates ?? ExchangeRates(fetch: { _ in ([:], Date()) }),
            bluetooth: BluetoothDevices(provider: bluetooth ?? StubBluetooth())
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
