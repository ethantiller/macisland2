import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MacIsland", systemImage: "capsule.fill") {
            if appDelegate.gate.isOpen {
                Button("Settings…") { SettingsWindowController.shared.show() }
                    .keyboardShortcut(",")
            } else {
                // Until setup is complete the guide is all there is.
                Button("Continue Setup") { appDelegate.continueSetup() }
            }
            Button("Quit MacIsland") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        // Modules the person put in the menu bar. None are there until they choose, or until setup is complete.
        ModuleMenuBars(viewModel: appDelegate.viewModel, panels: appDelegate.panels, gate: appDelegate.gate)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// First, so it tells an existing install from a fresh one before anything in this launch can write a key.
    let onboarding = OnboardingState()
    let gate = SetupGate()
    let features = AppDelegate.makeFeatures()

    private static func makeFeatures() -> IslandFeatures {
        let shelf = ShelfModel()
        let work = WorkTracker()
        let notes = NotesModel()
        let settings = AppSettings()
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
            settings: settings,
            agenda: AgendaMonitor(),
            focus: FocusMode(),
            clipboard: ClipboardHistory(),
            pomodoro: PomodoroModel(plan: { settings.pomodoroPlan }),
            work: work,
            weather: WeatherModel(),
            fileTools: FileTools(shelf: shelf, work: work),
            notes: notes,
            keyboardCleaner: KeyboardCleaner(),
            bluetooth: BluetoothDevices(provider: IOBluetoothProvider(), work: work),
            mirror: CameraMirror(provider: AVCameraProvider()),
            screenRecorder: ScreenRecorder(recorder: SCKScreenRecorder(), shelf: shelf),
            voice: VoiceRecorder(transcriber: SpeechVoiceTranscriber(), notes: notes, shelf: shelf),
            widgets: CustomWidgetValues(fetcher: LiveWidgetFetcher()),
            system: SystemModel(sampler: LiveSystemSampler()),
            agents: AgentActivity()
        )
    }

    lazy var viewModel = IslandViewModel(features: features)
    lazy var panels = FloatingPanels(viewModel: viewModel)
    lazy var urlCommands = URLCommandRunner(viewModel: viewModel)
    lazy var featureRunner = FeatureRunner(
        features: features, viewModel: viewModel,
        music: { [weak self] on in on ? self?.features.nowPlaying.start() : self?.features.nowPlaying.stop() },
        screenshots: { [weak self] on in on ? self?.screenshotWatcher.start() : self?.screenshotWatcher.stop() },
        agents: { [weak self] on in self?.applyAgents(on) }))
    private let batteryMonitor = BatteryMonitor()
    private let volumeMonitor = VolumeMonitor()
    private let screenshotWatcher = ScreenshotWatcher()
    private let agentWatcher = AgentLogWatcher()
    private let accessoryMonitor = AudioAccessoryMonitor()
    private let bluetoothAccess = BluetoothAccess()
    private let diskSpace = DiskSpace()
    private let hotkey = GlobalHotkey()
    private let shelfHotkey = GlobalHotkey(id: 2)
    private var panel: IslandPanel?
    private var mouseTracker: MouseTracker?
    private var menuHold: MenuHoldObserver?
    private let volumeHUD = VolumeHUDController()
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

        // The panel is ordered front when setup is complete (`updateSetupGate`), never before.
        let panel = IslandPanel(rootView: IslandView(viewModel: viewModel))
        self.panel = panel
        layout()

        mouseTracker = MouseTracker(panel: panel, viewModel: viewModel)
        mouseTracker?.isEnabled = false
        menuHold = MenuHoldObserver(viewModel: viewModel)
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
        features.fileTools.cleanUpStaging()
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
        connectVolumeHUD()
        connectStorage()
        connectDevices()
        connectCapture()

        // Nothing prompts at launch, on any install. What has a permission (Bluetooth, Downloads) starts when setup is complete and the
        // island appears (`startPermittedMonitors`): the guide asks.
        batteryMonitor.start()
        features.privacy.start()
        features.network.start()
        volumeMonitor.start()
        connectShelfChoices()
        connectFeatures()
    }

    /// Reads the agents' logs only while AI Agents is on: one FSEvents stream, torn down when it is off.
    private func applyAgents(_ on: Bool) {
        let features = features
        agentWatcher.stop()
        guard on else { return }
        let settings = features.settings
        features.agents.minimumDuration = { TimeInterval(settings.agentFinishMinimum) }
        agentWatcher.onBatch = { batch in
            guard settings.reads(batch.agent) else { return }
            for event in batch.events {
                features.agents.ingest(event, agent: batch.agent, session: batch.session)
            }
        }
        agentWatcher.onProcesses = { features.agents.setProcesses($0) }
        features.agents.onFinish = { [viewModel] _, duration in
            viewModel.flash(Announcements.agentDone(duration: duration), event: .agentDone)
        }
        agentWatcher.start()
    }

    /// What a switch in the Features catalog does beyond what each feature's own setting already does.
    private func connectFeatures() {
        let runner = featureRunner
        features.settings.onFeatureChange = { runner.apply($0) }
        // After everything else is connected: starts what is on (the music adapter), and nothing that would ask.
        runner.startAtLaunch()
    }

    /// The Shelf's own settings: what is swept, whether screenshots arrive, and whether the clipboard is watched.
    /// Each starts or stops its watcher, so a choice that turns something off also stops what it costs.
    private func connectShelfChoices() {
        let features = features
        viewModel.sweepShelf()

        let applyClipboard = {
            features.clipboard.setCapacity(features.settings.effectiveClipboardLimit)
        }
        features.settings.onClipboardChange = applyClipboard
        applyClipboard()

        let applyScreenshots = { [screenshotWatcher] in
            if FeatureRunner.wantsScreenshots(features.settings) {
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
        let apply = { features.weather.configure(city: FeatureRunner.weatherCity(features.settings)) }
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
            features.nowPlaying.lyrics.setEnabled(FeatureRunner.wantsLyrics(features.settings), for: features.nowPlaying.state)
        }
        features.settings.onLyricsChange = apply
        apply()
    }

    /// The island's own volume HUD, while Replace the Volume HUD is on. The tap exists only then.
    private func connectVolumeHUD() {
        let hud = volumeHUD
        let features = features
        let viewModel = viewModel
        hud.canShow = { viewModel.canShowVolumeHUD }
        // Clean Keys holds its own tap, and has the keys to itself while it does.
        hud.isSuspended = { features.keyboardCleaner.isLocked }
        hud.onShow = { viewModel.showVolume($0) }
        hud.onLostAccess = { [weak self] in
            // The permission was taken away: the tap is gone and the system's HUD is back. The setting follows, and says so.
            self?.features.settings.replacesVolumeHUD = false
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "speaker.wave.2.fill", tint: Theme.Tint.attention, title: "Volume HUD Turned Off",
                    detail: "Accessibility access was turned off"),
                for: .seconds(6), respectingFocus: false)
        }
        features.settings.onVolumeHUDChange = { [weak self] in self?.applyVolumeHUD(userInitiated: true) }
        // Back from System Settings, it tries again without asking.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyVolumeHUD(userInitiated: false) }
        }
        applyVolumeHUD(userInitiated: false)
    }

    /// Starts or stops the tap to match the setting. At launch, and on coming back to the app, it never asks for anything: without
    /// Accessibility it waits, and the system's HUD stays. Turning the setting on is the person's choice to be asked, so then it asks, leaves
    /// the setting off, and says what to do.
    private func applyVolumeHUD(userInitiated: Bool) {
        let settings = features.settings
        guard settings.replacesVolumeHUD else {
            volumeHUD.stop()
            return
        }
        switch volumeHUD.start() {
        case .started:
            break
        case .needsAccess:
            guard userInitiated else { return }
            settings.replacesVolumeHUD = false
            Task { await AccessCenter.model?.allow(.accessibility) }
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "hand.raised.fill", tint: Theme.Tint.attention, title: "Accessibility Access Needed",
                    detail: "Allow MacIsland in Accessibility, then turn this on again",
                    actions: [.init(title: "Open Settings") { KeyboardCleaner.openAccessibilitySettings() }]),
                for: .seconds(8), respectingFocus: false)
        case .failed:
            guard userInitiated else { return }
            settings.replacesVolumeHUD = false
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "speaker.wave.2.fill", tint: Theme.Tint.attention,
                    title: "Couldn\u{2019}t Take the Volume Keys", detail: "The system HUD is still in use"),
                for: .seconds(6), respectingFocus: false)
        }
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
        // A stale staging folder from a run that didn't quit cleanly goes now; nothing pending survives a launch.
        features.fileTools.cleanUpStaging()
        // A result waits in the Shelf for a choice; the alert stays until the island is opened, on the Shelf.
        features.fileTools.onResult = { [diskSpace] result in
            viewModel.flash(
                IslandAlert(
                    systemImage: "checkmark.circle.fill", tint: Theme.Tint.positive, text: result.verb,
                    staysUntilSeen: true, opensTab: .shelf),
                respectingFocus: false)
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

        // Turning a setting on is the choice to be asked, so its prompt may show. The launch only reads what macOS has decided.
        let applyAgenda = { (mayAsk: Bool) in
            FeatureRunner.configureAgenda(features, mayAsk: mayAsk)
        }
        features.settings.onAgendaChange = { applyAgenda(true) }
        applyAgenda(false)

        // Focus is only read once something needs it, so macOS asks at a moment that makes sense: when Quiet in Focus is turned on.
        // At launch it starts only if it was already allowed.
        let applyQuiet = { (atLaunch: Bool) in
            guard features.settings.quietDuringFocus, !atLaunch || FocusMode.isAuthorized else { return }
            features.focus.start()
        }
        features.settings.onQuietChange = { applyQuiet(false) }
        applyQuiet(true)
    }

    /// The first-run guide: what it needs from the app, its links, and the setup gate: the island appears only once the guide is
    /// finished and every permission is allowed, and the guide is what shows until then.
    private func connectOnboarding() {
        let onboarding = onboarding
        SettingsWindowController.shared.onboarding = onboarding
        let access = LiveAccess(agenda: features.agenda, bluetooth: bluetoothAccess, transfers: features.transfers)
        // Settings \u{2192} Privacy and the guide ask through this one, so a grant in either counts in both.
        let model = AccessModel(
            provider: access, settings: features.settings,
            onBluetoothAllowed: { [weak self] in self?.accessoryMonitor.start() })
        AccessCenter.model = model
        OnboardingWindowController.shared.context = OnboardingContext(
            features: features, island: viewModel, state: onboarding, access: model,
            guideEnded: { [weak self] in self?.updateSetupGate() },
            openSettings: { SettingsWindowController.shared.show() })
        urlCommands.onGuide = { reset in
            #if DEBUG
                if reset { onboarding.resetToFresh() }
            #endif
            OnboardingWindowController.shared.show(replay: !reset)
        }
        urlCommands.onTour = {
            onboarding.tourRequested = true
            SettingsWindowController.shared.show()
        }

        updateSetupGate()
        refreshSetupGate()
        // Back from System Settings, or from anywhere: a permission may have been turned off or on.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSetupGate() }
        }
    }

    /// Reads every permission again, the slow ones too, then settles the gate.
    private func refreshSetupGate() {
        Task { @MainActor in
            await AccessCenter.model?.refreshed()
            updateSetupGate()
        }
    }

    /// **Continue Setup** in the menu bar: the guide, from where it stopped.
    func continueSetup() {
        OnboardingWindowController.shared.show(replay: false, permissionsOnly: !onboarding.needsGuide)
    }

    /// Opens or closes the island to match setup. Complete (the guide finished, every permission allowed) opens it; anything less
    /// closes it and shows the guide, in its permissions-only form once the guide has been finished before. A guide still open when
    /// setup becomes complete (the permissions-only one) keeps the island closed until Done ends it.
    private func updateSetupGate() {
        guard let access = AccessCenter.model else { return }
        let complete = SetupGate.isComplete(needsGuide: onboarding.needsGuide, allAllowed: access.allAllowed)
        let guideIsOpen = OnboardingWindowController.shared.isOpen
        if complete {
            if !(guideIsOpen && !gate.isOpen) { openGate() }
        } else {
            closeGate()
            if !guideIsOpen { continueSetup() }
        }
    }

    private func openGate() {
        guard !gate.isOpen else { return }
        gate.open()
        mouseTracker?.isEnabled = true
        panel?.orderFrontRegardless()
        startPermittedMonitors()
    }

    private func closeGate() {
        gate.close()
        viewModel.closePinned()
        mouseTracker?.isEnabled = false
        panel?.orderOut(nil)
        panels.closeAll()
    }

    /// Starts the monitors that have a permission, when it is allowed, and never prompts: Bluetooth, and Downloads once it reads as
    /// allowed. Run when the island appears. Safe to call again.
    private func startPermittedMonitors() {
        if BluetoothAccess.isAllowed { accessoryMonitor.start() }
        if AccessAsked.contains(.downloads), PrivacyAccess.downloadsFolderIsReadable() { features.transfers.start() }
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
        let keys: [ShortcutSlot: GlobalHotkey] = [.open: hotkey, .shelf: shelfHotkey]
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
        AppRelaunch.beforeRelaunch = { [hotkey, shelfHotkey] in
            hotkey.unregister()
            shelfHotkey.unregister()
        }

        // A key the copy that is quitting still held (a relaunch starts the new one first) is free within a moment: try again for
        // about 3 seconds, then say it failed.
        Task { @MainActor in
            for attempt in 1...6 {
                let missing = ShortcutSlot.allCases.filter { slot in
                    guard let key = keys[slot], settings.shortcut(slot) != nil else { return false }
                    return !key.isRegistered
                }
                if missing.isEmpty { return }
                try? await Task.sleep(for: .milliseconds(500))
                for slot in missing { _ = apply(slot, settings.shortcut(slot)) }
                if attempt == 6 {
                    let stillMissing = missing.filter { !(keys[$0]?.isRegistered ?? true) }
                    for slot in stillMissing { HotkeyLog.logger.error("shortcut \(slot.rawValue) could not be registered") }
                }
            }
        }
    }

    /// Control-Option-Space opens the island and gives it the keyboard: Esc closes, arrows switch tabs.
    private func connectKeyboard(panel: IslandPanel) {
        let viewModel = viewModel
        let gate = gate
        hotkey.onPress = { [weak panel] in
            // While the first-run guide is up, the shortcut is practised on the island in its window, not on this one. Before setup is
            // complete it goes nowhere else.
            if OnboardingWindowController.shared.handleOpenShortcut() { return }
            guard gate.isOpen else { return }
            viewModel.toggleFromKeyboard()
            if viewModel.isPinnedOpen { panel?.makeKey() }
        }
        shelfHotkey.onPress = { [weak panel] in
            guard gate.isOpen else { return }
            viewModel.toggleShelfFromKeyboard()
            if viewModel.isPinnedOpen { panel?.makeKey() }
        }
        registerShortcuts()

        viewModel.onWantsKeyboard = { [weak panel] in panel?.makeKey() }
        viewModel.onReleaseKeyboard = { [weak panel] in
            // The panel is not the app's main window, so ordering it out and back hands the keyboard to the app behind it.
            panel?.orderOut(nil)
            panel?.orderFrontRegardless()
        }
        panel.keyHandler = { keyCode, modifiers in
            switch Int(keyCode) {
            case kVK_Escape: if !viewModel.stepBack() { viewModel.closePinned() }
            case kVK_LeftArrow: viewModel.selectAdjacentTab(-1)
            case kVK_RightArrow: viewModel.selectAdjacentTab(1)
            case kVK_Space: return viewModel.quickLookHoveredItem()
            case kVK_Return, kVK_ANSI_KeypadEnter: return viewModel.pasteFirstClipboardMatch()
            default:
                guard modifiers.contains(.command), let digit = ClipboardShortcut.digit(forKeyCode: keyCode) else {
                    return false
                }
                return viewModel.pasteClipboardShortcut(digit)
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
    let gate: SetupGate

    var body: some Scene {
        menuBar(.home)
        menuBar(.media)
        menuBar(.shelf)
        menuBar(.clock)
        menuBar(.reminders)
        menuBar(.tools)
        menuBar(.notes)
        menuBar(.agents)
    }

    private func menuBar(_ module: IslandModule) -> some Scene {
        MenuBarExtra(
            module.title,
            systemImage: module.systemImage,
            isInserted: Binding(
                get: { gate.isOpen && viewModel.settings.showsInMenuBar(module) },
                set: { if gate.isOpen, viewModel.settings.isShown(module) { viewModel.settings.setInMenuBar(module, $0) } }
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
