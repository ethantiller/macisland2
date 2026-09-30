import AppKit
@testable import MacIsland

/// One place that builds a view model from test doubles, so adding a feature to
/// `IslandFeatures` only changes this file.
@MainActor
enum TestSupport {
    static func makeViewModel() -> IslandViewModel {
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
            fileTools: FileTools(shelf: shelf, work: work),
            notes: NotesModel(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            keyboardCleaner: KeyboardCleaner(),
            launch: LaunchModel(appDirectories: []),
            stats: SystemStats()
        ))
        viewModel.geometry = geometry
        return viewModel
    }
}
