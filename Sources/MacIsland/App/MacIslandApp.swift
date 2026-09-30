import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MacIsland", systemImage: "capsule.fill") {
            Button("Command Palette") { appDelegate.palette.toggle() }
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Button("Quit MacIsland") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings { SettingsView(settings: appDelegate.features.settings) }
        // Modules the person put in the menu bar. None are there until they choose.
        ModuleMenuBars(viewModel: appDelegate.viewModel, panels: appDelegate.panels)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let features = AppDelegate.makeFeatures()

    private static func makeFeatures() -> IslandFeatures {
        let shelf = ShelfModel()
        let work = WorkTracker()
        return IslandFeatures(
            nowPlaying: NowPlayingModel(),
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
            settings: AppSettings(),
            agenda: AgendaMonitor(),
            focus: FocusMode(),
            clipboard: ClipboardHistory(),
            batteries: DeviceBatteries(),
            pomodoro: PomodoroModel(),
            work: work,
            weather: WeatherModel(),
            fileTools: FileTools(shelf: shelf, work: work),
            notes: NotesModel(),
            keyboardCleaner: KeyboardCleaner(),
        launch: LaunchModel(),
            stats: SystemStats(),
            rates: ExchangeRates(),
            bluetooth: BluetoothDevices(provider: IOBluetoothProvider(), work: work)
        )
    }

    lazy var viewModel = IslandViewModel(features: features)
    lazy var panels = FloatingPanels(viewModel: viewModel)
    lazy var palette = PaletteController(viewModel: viewModel)
    lazy var urlCommands = URLCommandRunner(viewModel: viewModel) { [palette] in palette.show() }
    private let paletteHotkey = GlobalHotkey(id: 2)
    private let batteryMonitor = BatteryMonitor()
    private let volumeMonitor = VolumeMonitor()
    private let screenshotWatcher = ScreenshotWatcher()
    private let accessoryMonitor = AudioAccessoryMonitor()
    private let diskSpace = DiskSpace()
    private let hotkey = GlobalHotkey()
    private var panel: IslandPanel?
    private var mouseTracker: MouseTracker?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also covers `swift run`, where there's no Info.plist to set LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        // Quit normally on SIGTERM (e.g. `pkill`) so the adapter subprocess gets stopped.
        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { NSApp.terminate(nil) }
        sigterm.resume()
        sigtermSource = sigterm

        connectEvents()

        let panel = IslandPanel(rootView: IslandView(viewModel: viewModel))
        self.panel = panel
        layout()
        panel.orderFrontRegardless()

        mouseTracker = MouseTracker(panel: panel, viewModel: viewModel)
        connectKeyboard(panel: panel)
        connectReach()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urlCommands.handle(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        features.notes.save()
        features.nowPlaying.stop()
    }

    private func connectEvents() {
        let viewModel = viewModel
        let features = features

        features.timer.onFinish = {
            viewModel.flash(IslandAlert(
                systemImage: "bell.fill", tint: Theme.Tint.clock, text: "Done", staysUntilSeen: true, opensTab: .clock
            ))
        }

        features.pomodoro.onPhaseEnd = { finished, next in
            let isBreak = next != .focus
            viewModel.flash(IslandAlert(
                systemImage: isBreak ? "cup.and.saucer.fill" : "brain.head.profile",
                tint: Theme.Tint.clock,
                text: finished == .longBreak ? "Done" : next.title,
                staysUntilSeen: true,
                opensTab: .clock
            ))
        }

        batteryMonitor.onEvent = { event in
            switch event {
            case .charging(let percent):
                viewModel.flash(IslandAlert(
                    systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "\(percent)%", isCharging: true
                ))
            case .full(let percent):
                viewModel.flash(IslandAlert(
                    systemImage: "battery.100percent", tint: Theme.Tint.positive, text: "\(percent)%"
                ))
            case .low(let percent):
                let lowPower = features.lowPower
                viewModel.showBanner(
                    IslandBanner(
                        systemImage: "battery.25percent",
                        tint: Theme.Tint.attention,
                        title: "Low Battery",
                        detail: "\(percent)% remaining",
                        action: lowPower.isOn ? nil : .init(title: "Low Power Mode") { lowPower.toggle() }
                    ),
                    for: .seconds(6),
                    followUp: IslandAlert(
                        systemImage: "battery.25percent", tint: Theme.Tint.attention, text: "\(percent)%",
                        staysUntilSeen: true, opensTab: .tools
                    )
                )
            }
        }

        batteryMonitor.fullChargeLevel = { features.settings.fullChargeLevel }

        accessoryMonitor.onConnect = { accessory in
            viewModel.showBanner(IslandBanner(
                systemImage: accessory.systemImage,
                tint: Theme.Tint.neutral,
                title: accessory.name,
                detail: accessory.batterySummary ?? "Connected"
            ))
        }

        features.network.onHotspotConnect = {
            viewModel.flash(IslandAlert(systemImage: "personalhotspot", tint: Theme.Tint.positive, text: "Hotspot"))
        }

        features.transfers.onFinish = { [diskSpace] _ in
            viewModel.flash(IslandAlert(systemImage: "arrow.down.circle.fill", tint: Theme.Tint.positive, text: "Saved"))
            diskSpace.check()
        }

        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [diskSpace] _ in
            MainActor.assumeIsolated {
                viewModel.flash(
                    IslandAlert(systemImage: "touchid", tint: Theme.Tint.positive, text: "Unlocked"),
                    for: .seconds(2)
                )
                diskSpace.check()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [diskSpace] _ in
            MainActor.assumeIsolated { diskSpace.check() }
        }

        connectAgenda()
        connectWeather()
        connectLyrics()
        connectStorage()
        connectDevices()

        batteryMonitor.start()
        accessoryMonitor.start()
        features.privacy.start()
        features.transfers.start()
        features.network.start()
        features.clipboard.start()
        volumeMonitor.start()
        screenshotWatcher.start()
    }

    /// Low disk space, and Bluetooth devices that would not connect.
    private func connectDevices() {
        let viewModel = viewModel
        diskSpace.onLow = { free in
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "internaldrive.fill",
                    tint: Theme.Tint.attention,
                    title: "Low Disk Space",
                    detail: DiskSpace.description(free: free),
                    action: .init(title: "Open Storage") { DiskSpace.openStorageSettings() }
                ),
                for: .seconds(6),
                followUp: IslandAlert(
                    systemImage: "internaldrive.fill", tint: Theme.Tint.attention,
                    text: ByteCountFormatter.string(fromByteCount: free, countStyle: .file), staysUntilSeen: true
                ),
                respectingFocus: false
            )
        }
        features.bluetooth.onFailure = { _ in
            viewModel.flash(BluetoothDevices.failureAlert(), respectingFocus: false)
        }
    }

    /// The weather follows the city in Settings, and stops when it is emptied.
    private func connectWeather() {
        let features = features
        let apply = { features.weather.configure(city: features.settings.weatherCity) }
        features.weather.onRainSoon = { [viewModel] start in
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "cloud.rain.fill",
                    tint: Theme.Tint.neutral,
                    title: "Rain Soon",
                    detail: "Starts around \(start.formatted(date: .omitted, time: .shortened))"
                ),
                for: .seconds(6)
            )
        }
        features.settings.onWeatherChange = apply
        apply()
    }

    /// Lyrics are looked up only while Synced Lyrics is on in Settings.
    private func connectLyrics() {
        let features = features
        let apply = {
            features.nowPlaying.lyrics.setEnabled(features.settings.showsLyrics, for: features.nowPlaying.state)
        }
        features.settings.onLyricsChange = apply
        apply()
    }

    /// Drives offer Eject when they mount; new screenshots land on the Shelf.
    private func connectStorage() {
        let viewModel = viewModel
        let shelf = features.shelf

        volumeMonitor.onMount = { volume in
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "externaldrive.fill",
                    tint: Theme.Tint.neutral,
                    title: volume.name,
                    detail: volume.detail,
                    action: .init(title: "Eject") {
                        // Off the main thread, and reported after the banner has dismissed itself.
                        Task.detached {
                            let reason = VolumeMonitor.eject(volume)
                            await MainActor.run { Self.reportEject(of: volume, failure: reason, on: viewModel) }
                        }
                    }
                ),
                for: .seconds(8)
            )
        }

        features.fileTools.onDone = { [diskSpace] word in
            viewModel.flash(IslandAlert(systemImage: "checkmark.circle.fill", tint: Theme.Tint.positive, text: word))
            diskSpace.check()
        }
        features.fileTools.onNote = { note in viewModel.flash(note, respectingFocus: false) }
        features.fileTools.onFail = { reason in
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.Tint.attention,
                    title: "Couldn\u{2019}t Finish",
                    detail: reason
                ),
                for: .seconds(6),
                respectingFocus: false
            )
        }

        screenshotWatcher.onScreenshot = { url in
            shelf.add([url])
            viewModel.flash(IslandAlert(systemImage: "camera.viewfinder", tint: Theme.Tint.positive, text: "Shelf"))
        }
    }

    private static func reportEject(of volume: VolumeMonitor.Volume, failure: String?, on viewModel: IslandViewModel) {
        if let failure {
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "externaldrive.badge.exclamationmark",
                    tint: Theme.Tint.attention,
                    title: "Couldn\u{2019}t Eject \(volume.name)",
                    detail: failure
                ),
                for: .seconds(6),
                respectingFocus: false
            )
        } else {
            viewModel.flash(
                IslandAlert(systemImage: "eject.fill", tint: Theme.Tint.positive, text: "Ejected"),
                respectingFocus: false
            )
        }
    }

    /// Calendar and Reminders are asked for only once they are turned on in Settings.
    private func connectAgenda() {
        let viewModel = viewModel
        let features = features

        features.agenda.onAnnounce = { item in
            let action = AgendaAction(item: item, agenda: features.agenda)
            let isEvent = item.kind == .event
            viewModel.showBanner(
                IslandBanner(
                    systemImage: isEvent ? "calendar" : "checklist",
                    tint: Theme.Tint.neutral,
                    title: item.title,
                    detail: isEvent ? AgendaRules.timeText(for: item, now: Date()) : "Due now",
                    action: action.map { action in .init(title: action.title, perform: action.perform) }
                ),
                for: .seconds(8)
            )
        }

        let applyAgenda = {
            features.agenda.configure(calendar: features.settings.showsCalendar, reminders: features.settings.showsReminders)
        }
        features.settings.onAgendaChange = applyAgenda
        applyAgenda()
        features.agenda.start()

        // Focus is only read once something needs it, so macOS asks at a moment that makes sense.
        let applyQuiet = {
            if features.settings.quietDuringFocus { features.focus.start() }
        }
        features.settings.onQuietChange = applyQuiet
        applyQuiet()
    }

    /// The command palette on Control-Option-K, and windows torn off the island.
    private func connectReach() {
        viewModel.onOpenWindow = { [panels] module in panels.open(module) }
        palette.onOpenSettings = {
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        paletteHotkey.onPress = { [palette] in palette.toggle() }
        paletteHotkey.register(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))
    }

    /// Control-Option-Space opens the island and gives it the keyboard: Esc closes, arrows switch tabs.
    private func connectKeyboard(panel: IslandPanel) {
        let viewModel = viewModel
        hotkey.onPress = { [weak panel] in
            viewModel.toggleFromKeyboard()
            if viewModel.isPinnedOpen { panel?.makeKey() }
        }
        let apply: (HotkeyChoice) -> Void = { [hotkey] choice in
            if let combo = choice.keyCombo {
                hotkey.register(keyCode: combo.keyCode, modifiers: combo.modifiers)
            } else {
                hotkey.unregister()
            }
        }
        features.settings.onHotkeyChange = apply
        apply(features.settings.hotkey)

        viewModel.onWantsKeyboard = { [weak panel] in panel?.makeKey() }
        panel.keyHandler = { keyCode in
            switch Int(keyCode) {
            case kVK_Escape: viewModel.closePinned()
            case kVK_LeftArrow: viewModel.selectAdjacentTab(-1)
            case kVK_RightArrow: viewModel.selectAdjacentTab(1)
            case kVK_Space: return viewModel.quickLookHoveredItem()
            default: return false
            }
            return true
        }
    }

    private func layout() {
        guard let panel else { return }
        let geometry = ScreenGeometry.current()
        viewModel.geometry = geometry
        panel.setFrame(geometry.panelFrame, display: true)
    }
}

/// One menu-bar extra per module, inserted only while the person has chosen it (in Settings, or from a tab's
/// menu). Dragging the extra off the bar removes it.
struct ModuleMenuBars: Scene {
    let viewModel: IslandViewModel
    let panels: FloatingPanels

    var body: some Scene {
        menuBar(.home)
        menuBar(.media)
        menuBar(.shelf)
        menuBar(.clock)
        menuBar(.reminders)
        menuBar(.tools)
        menuBar(.notes)
    }

    private func menuBar(_ module: IslandModule) -> some Scene {
        MenuBarExtra(
            module.title,
            systemImage: module.systemImage,
            isInserted: Binding(
                get: { viewModel.settings.isInMenuBar(module) },
                set: { viewModel.settings.setInMenuBar(module, $0) }
            )
        ) {
            MenuBarModuleView(module: module, viewModel: viewModel, panels: panels)
        }
        .menuBarExtraStyle(.window)
    }
}

/// A module in a menu-bar window. The header pops it out into a window of its own: click the button, or drag it away.
struct MenuBarModuleView: View {
    let module: IslandModule
    let viewModel: IslandViewModel
    let panels: FloatingPanels

    @State private var didTearOff = false

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            HStack(spacing: 4) {
                Label(module.title, systemImage: module.systemImage)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                Spacer(minLength: 8)
                Image(systemName: "line.3.horizontal")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .help("Drag away to open in a window")
                    .accessibilityHidden(true)
                IconButton(systemName: "macwindow", label: "Open \(module.title) in a Window", size: 12) { tearOff() }
            }
            .frame(height: Theme.Metrics.detachedHeaderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 16).onChanged { _ in
                    guard !didTearOff else { return }
                    didTearOff = true
                    tearOff(at: NSEvent.mouseLocation)
                }
                .onEnded { _ in didTearOff = false }
            )

            ModuleContent(module: module, viewModel: viewModel)
                .frame(width: Theme.Metrics.detachedWidth, height: viewModel.contentHeight(for: module), alignment: .top)
        }
        .padding(Theme.Metrics.floatPadding)
        // The menu-bar window brings its own material; ink follows the system appearance.
        .environment(\.islandSurface, .glass)
        .environment(\.isFloatingWindow, true)
    }

    private func tearOff(at point: NSPoint? = nil) {
        NSApp.keyWindow?.orderOut(nil)
        panels.open(module, at: point)
    }
}
