import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MacIsland", systemImage: "capsule.fill") {
            Button("Settings…") { SettingsWindowController.shared.show() }
                .keyboardShortcut(",")
            Button("Quit MacIsland") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        // Modules the person put in the menu bar. None are there until they choose.
        ModuleMenuBars(viewModel: appDelegate.viewModel, panels: appDelegate.panels)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// First, so it tells an existing install from a fresh one before anything in this launch can write a key.
    let onboarding = OnboardingState()
    let features = AppDelegate.makeFeatures()

    private static func makeFeatures() -> IslandFeatures {
        let shelf = ShelfModel()
        let work = WorkTracker()
        let notes = NotesModel()
        return IslandFeatures(
            nowPlaying: NowPlayingModel(),
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
            settings: AppSettings(),
            agenda: AgendaMonitor(),
            focus: FocusMode(),
            clipboard: ClipboardHistory(),
            pomodoro: PomodoroModel(),
            work: work,
            weather: WeatherModel(),
            fileTools: FileTools(shelf: shelf, work: work),
            notes: notes,
            keyboardCleaner: KeyboardCleaner(),
            bluetooth: BluetoothDevices(provider: IOBluetoothProvider(), work: work),
            mirror: CameraMirror(provider: AVCameraProvider()),
            screenRecorder: ScreenRecorder(recorder: SCKScreenRecorder(), shelf: shelf),
            voice: VoiceRecorder(transcriber: SpeechVoiceTranscriber(), notes: notes, shelf: shelf),
            widgets: CustomWidgetValues(fetcher: LiveWidgetFetcher())
        )
    }

    lazy var viewModel = IslandViewModel(features: features)
    lazy var panels = FloatingPanels(viewModel: viewModel)
    lazy var urlCommands = URLCommandRunner(viewModel: viewModel)
    private let batteryMonitor = BatteryMonitor()
    private let volumeMonitor = VolumeMonitor()
    private let screenshotWatcher = ScreenshotWatcher()
    private let accessoryMonitor = AudioAccessoryMonitor()
    private let bluetoothAccess = BluetoothAccess()
    private let diskSpace = DiskSpace()
    private let hotkey = GlobalHotkey()
    private var panel: IslandPanel?
    private var mouseTracker: MouseTracker?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also covers `swift run`, where there's no Info.plist to set LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        SettingsWindowController.shared.features = features

        // Quit normally on SIGTERM (e.g. `pkill`) so the adapter subprocess gets stopped.
        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { NSApp.terminate(nil) }
        sigterm.resume()
        sigtermSource = sigterm

        connectEvents()
        features.settings.onDisplayChange = { [weak self] in self?.layout() }

        let panel = IslandPanel(rootView: IslandView(viewModel: viewModel))
        self.panel = panel
        layout()
        panel.orderFrontRegardless()

        mouseTracker = MouseTracker(panel: panel, viewModel: viewModel)
        connectKeyboard(panel: panel)
        connectReach()
        connectOnboarding()

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
            viewModel.flash(
                IslandAlert(
                    systemImage: "bell.fill", tint: Theme.Tint.clock, text: "Done", staysUntilSeen: true,
                    opensTab: .clock
                ))
        }

        features.pomodoro.onPhaseEnd = { finished, next in
            let isBreak = next != .focus
            viewModel.flash(
                IslandAlert(
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
                viewModel.flash(Announcements.charging(percent: percent), event: .charging)
            case .full(let percent):
                viewModel.flash(Announcements.fullCharge(percent: percent), event: .fullCharge)
            case .low(let percent):
                let low = Announcements.lowBattery(percent: percent)
                viewModel.showBanner(low.banner, for: .seconds(6), followUp: low.followUp, event: .lowBattery)
            }
        }

        batteryMonitor.fullChargeLevel = { features.settings.fullChargeLevel }

        accessoryMonitor.onConnect = { accessory in
            viewModel.showBanner(Announcements.headphones(accessory), event: .headphones)
        }

        features.network.onHotspotConnect = {
            viewModel.flash(Announcements.hotspot, event: .hotspot)
        }

        features.transfers.onFinish = { [diskSpace] _ in
            viewModel.flash(Announcements.downloadSaved, event: .download)
            diskSpace.check()
        }

        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [diskSpace] _ in
            MainActor.assumeIsolated {
                viewModel.flash(Announcements.unlocked, for: .seconds(2), event: .unlocked)
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
        connectCapture()

        // A fresh install's first launches hold back what would prompt on its own (Bluetooth, Downloads): the guide asks at a
        // moment of its own, and starts them when it ends.
        let holdsPrompts = onboarding.holdsLaunchPrompts
        batteryMonitor.start()
        if !holdsPrompts { accessoryMonitor.start() }
        features.privacy.start()
        if !holdsPrompts { features.transfers.start() }
        features.network.start()
        volumeMonitor.start()
        connectShelfChoices()
    }

    /// The Shelf's own settings: what is swept, whether screenshots arrive, and whether the clipboard is watched.
    /// Each starts or stops its watcher, so a choice that turns something off also stops what it costs.
    private func connectShelfChoices() {
        let features = features
        viewModel.sweepShelf()

        let applyClipboard = {
            features.clipboard.setCapacity(features.settings.clipboardLimit)
        }
        features.settings.onClipboardChange = applyClipboard
        applyClipboard()

        let applyScreenshots = { [screenshotWatcher] in
            if features.settings.addsScreenshots {
                screenshotWatcher.start()
            } else {
                screenshotWatcher.stop()
            }
        }
        features.settings.onScreenshotsChange = applyScreenshots
        applyScreenshots()
    }

    /// Screen recordings and voice notes: what they leave behind, and what to do when they can't start.
    private func connectCapture() {
        let viewModel = viewModel
        let features = features

        features.screenRecorder.onFinish = { _ in
            viewModel.flash(
                IslandAlert(systemImage: "record.circle.fill", tint: Theme.Tint.positive, text: "Saved"),
                respectingFocus: false)
        }
        features.screenRecorder.onNeedsAccess = {
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "record.circle",
                    tint: Theme.Tint.attention,
                    title: "Screen Recording Access Needed",
                    detail: "Allow it to record the screen",
                    actions: [.init(title: "Open Settings") { ScreenRecorder.openScreenRecordingSettings() }]
                ),
                for: .seconds(8),
                respectingFocus: false
            )
        }
        features.screenRecorder.onFail = { reason in
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "record.circle", tint: Theme.Tint.attention, title: "Couldn\u{2019}t Record",
                    detail: reason
                ),
                for: .seconds(6),
                respectingFocus: false
            )
        }

        features.voice.onSaved = {
            viewModel.flash(
                IslandAlert(systemImage: "waveform", tint: Theme.Tint.positive, text: "Saved"), respectingFocus: false)
        }
        features.voice.onFail = { error in
            let denied = (error as? VoiceError) == .microphoneDenied
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "mic.slash.fill",
                    tint: Theme.Tint.attention,
                    title: "Couldn\u{2019}t Record",
                    detail: error.localizedDescription,
                    actions: denied ? [.init(title: "Open Settings") { VoiceRecorder.openMicrophoneSettings() }] : []
                ),
                for: .seconds(8),
                respectingFocus: false
            )
        }
    }

    /// Low disk space, and Bluetooth devices that would not connect.
    private func connectDevices() {
        let viewModel = viewModel
        diskSpace.onLow = { free in
            let low = Announcements.lowDisk(free: free)
            viewModel.showBanner(
                low.banner, for: .seconds(6), followUp: low.followUp, respectingFocus: false, event: .lowDisk)
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
            viewModel.showBanner(Announcements.rainSoon(start: start), for: .seconds(6), event: .rainSoon)
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
            let banner = Announcements.drive(volume) {
                // Off the main thread, and reported after the banner has dismissed itself.
                Task.detached {
                    let reason = VolumeMonitor.eject(volume)
                    await MainActor.run { Self.reportEject(of: volume, failure: reason, on: viewModel) }
                }
            }
            viewModel.showBanner(banner, for: .seconds(8), event: .drive)
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
            viewModel.showBanner(
                AgendaAction.announcement(for: item, agenda: features.agenda) { viewModel.startMirror() },
                for: .seconds(8), event: item.kind == .event ? .meeting : .reminderDue
            )
        }

        let applyAgenda = {
            features.agenda.configure(
                calendar: features.settings.showsCalendar, reminders: features.settings.showsReminders)
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

    /// The first-run guide: what it needs from the app, its links, and showing it at the end of launch when this install hasn't
    /// seen it.
    private func connectOnboarding() {
        let onboarding = onboarding
        SettingsWindowController.shared.onboarding = onboarding
        OnboardingWindowController.shared.context = OnboardingContext(
            features: features, island: viewModel, state: onboarding,
            access: LiveAccess(agenda: features.agenda, bluetooth: bluetoothAccess),
            startDeferredMonitors: { [weak self] in self?.startDeferredMonitors() },
            startAccessoryMonitor: { [weak self] in self?.accessoryMonitor.start() },
            openSettings: { SettingsWindowController.shared.show() })
        urlCommands.onGuide = { reset in
            #if DEBUG
                if reset { onboarding.resetToFresh() }
            #endif
            OnboardingWindowController.shared.show(replay: !reset)
        }
        if onboarding.needsGuide { OnboardingWindowController.shared.show(replay: false) }
    }

    /// Starts what `connectEvents` starts, for anything it held back. Safe to call again.
    private func startDeferredMonitors() {
        accessoryMonitor.start()
        features.transfers.start()
    }

    /// Windows torn off the island, and opening Settings from it.
    private func connectReach() {
        viewModel.onOpenWindow = { [panels] module in panels.open(module) }
        viewModel.onOpenSettings = { [settings = features.settings] pane, selection in
            UserDefaults.standard.set(pane.rawValue, forKey: "settings.pane")
            settings.requestedHomeSelection = selection
            SettingsWindowController.shared.show()
        }
    }

    /// Registers the global shortcut, and lets Settings change it: a key another app already owns is refused there,
    /// and the old one stays.
    private func registerShortcuts() {
        let settings = features.settings
        let keys: [ShortcutSlot: GlobalHotkey] = [.open: hotkey]
        func apply(_ slot: ShortcutSlot, _ combo: KeyCombo?) -> Bool {
            guard let key = keys[slot] else { return false }
            guard let combo else {
                key.unregister()
                return true
            }
            if key.register(keyCode: combo.keyCode, modifiers: combo.modifiers) { return true }
            // Taken: put the old one back.
            if let old = settings.shortcut(slot) { key.register(keyCode: old.keyCode, modifiers: old.modifiers) }
            return false
        }
        settings.shortcutRegistrar = apply
        for slot in ShortcutSlot.allCases { _ = apply(slot, settings.shortcut(slot)) }
    }

    /// Control-Option-Space opens the island and gives it the keyboard: Esc closes, arrows switch tabs.
    private func connectKeyboard(panel: IslandPanel) {
        let viewModel = viewModel
        hotkey.onPress = { [weak panel] in
            viewModel.toggleFromKeyboard()
            if viewModel.isPinnedOpen { panel?.makeKey() }
        }
        registerShortcuts()

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
        let geometry = ScreenGeometry.current(display: features.settings.islandDisplay)
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
                .frame(
                    width: Theme.Metrics.detachedWidth, height: viewModel.contentHeight(for: module), alignment: .top)
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
