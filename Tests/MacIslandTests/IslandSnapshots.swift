import AppKit
import CoreAudio
import SwiftUI
import Testing

@testable import MacIsland

/// Renders each island state to PNGs for design review. Opt-in:
/// `ISLAND_SNAPSHOT_DIR=/some/dir ./scripts/test.sh --filter IslandSnapshots`
@MainActor
struct IslandSnapshots {
    private let outputDirectory = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"].map(
        URL.init(fileURLWithPath:))

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderStates() async throws {
        let viewModel = makeViewModel()

        render(viewModel, "01-compact-idle")

        var paused = sampleTrack()
        paused.isPlaying = false
        viewModel.nowPlaying.apply(paused)
        render(viewModel, "02-compact-media-paused")

        viewModel.nowPlaying.apply(sampleTrack())
        render(viewModel, "03-compact-media-playing")

        viewModel.setHovering(true)
        render(viewModel, "01b-compact-swell")
        viewModel.setHovering(false)

        viewModel.state = .peek
        render(viewModel, "03b-peek-media")

        // Home, with weather from a stubbed Open-Meteo.
        let weather = viewModel.weather
        weather.typingPause = .zero
        weather.usesFahrenheit = false
        weather.fetch = PreviewSamples.weatherResponse
        weather.configure(city: "Paris")
        try await Task.sleep(for: .milliseconds(100))
        let playing = viewModel.nowPlaying.state
        viewModel.nowPlaying.apply(NowPlayingState())
        viewModel.state = .peek
        render(viewModel, "03e-peek-idle-weather")
        viewModel.nowPlaying.apply(playing)
        viewModel.state = .expanded
        viewModel.selectedTab = .home
        render(viewModel, "04a-expanded-home")
        viewModel.setCalendarExpanded(true)
        render(viewModel, "04a-expanded-home-calendar")
        viewModel.setCalendarExpanded(false)
        for (index, preset) in HomeLayout.presets.enumerated() {
            viewModel.settings.setHomeLayout(preset.layout)
            render(viewModel, "04f-home-preset-\(index + 1)-\(preset.name.lowercased())")
        }
        // Three rows, every cell taken: the tallest Home, in the tallest panel.
        viewModel.settings.setHomeLayout(
            HomeLayout(widgets: [
                WidgetPlacement(widget: .builtIn(.today), size: GridSize(3, 1)),
                WidgetPlacement(widget: .builtIn(.music), size: GridSize(3, 1)),
                WidgetPlacement(widget: .builtIn(.quickTools), size: GridSize(1, 1)),
                WidgetPlacement(widget: .builtIn(.clockActions), size: GridSize(5, 1)),
                WidgetPlacement(widget: .builtIn(.weather), size: GridSize(1, 1)),
                WidgetPlacement(widget: .builtIn(.battery), size: GridSize(1, 1)),
                WidgetPlacement(widget: .builtIn(.reminders), size: GridSize(2, 1)),
                WidgetPlacement(widget: .builtIn(.note), size: GridSize(2, 1)),
            ]))
        render(viewModel, "04a-expanded-home-three-rows")
        viewModel.settings.setHomeLayout(.default)
        viewModel.timer.start(minutes: 25)
        render(viewModel, "04a-expanded-home-timer-strip")
        viewModel.timer.reset()
        viewModel.settings.move(.notes, to: .right)
        render(viewModel, "04e-right-tab")
        viewModel.timer.start(minutes: 25)
        render(viewModel, "04e-right-tab-timer")
        viewModel.timer.reset()
        viewModel.settings.setEnabled(.notes, false)

        viewModel.state = .expanded
        viewModel.selectedTab = .media
        render(viewModel, "04-expanded-media")

        let lyrics = viewModel.nowPlaying.lyrics
        lyrics.fetch = { _ in
            Data(#"{"syncedLyrics": "[00:00.00] Waiting in a car, waiting for a ride in the dark"}"#.utf8)
        }
        lyrics.setEnabled(true, for: NowPlayingState())
        viewModel.nowPlaying.apply(sampleTrack())
        viewModel.nowPlaying.toggleShuffle()
        viewModel.nowPlaying.cycleRepeat()
        try await Task.sleep(for: .milliseconds(100))
        // The pointer-left step earlier schedules a close 300 ms later, which may have landed by now.
        viewModel.state = .expanded
        render(viewModel, "04b-expanded-media-lyrics")
        viewModel.state = .peek
        render(viewModel, "03d-peek-media-lyrics")
        viewModel.state = .expanded
        lyrics.setEnabled(false, for: viewModel.nowPlaying.state)

        viewModel.selectedTab = .shelf
        render(viewModel, "05-expanded-shelf-empty")

        viewModel.selectedTab = .shelf
        viewModel.setShelfMode(.clipboard)
        viewModel.clipboard.record(.text("https://example.com/a-long-link-to-share"))
        viewModel.clipboard.record(.text("Meeting notes: ship the island"))
        viewModel.clipboard.record(.text("#FF5733"))
        viewModel.clipboard.record(.text("hello@example.com"))
        render(viewModel, "05b-expanded-clipboard")
        viewModel.setShelfMode(.files)

        viewModel.timer.start(minutes: 25)
        viewModel.selectedTab = .clock
        render(viewModel, "06-expanded-timer")

        // Setting a timer: the ruler at rest, past an hour, and mid-scrub between two minutes.
        viewModel.timer.reset()
        viewModel.timer.setDuration(minutes: 5)
        render(viewModel, "06c-expanded-timer-setter")
        viewModel.timer.setDuration(minutes: 65)
        render(viewModel, "06d-expanded-timer-setter-hour")
        viewModel.timer.setDuration(minutes: 5)
        viewModel.scrubDial(byFingerDX: -299.2)
        render(viewModel, "06e-expanded-timer-setter-scrub")
        viewModel.endDialScrub()
        viewModel.timer.start(minutes: 25)

        viewModel.clockMode = .pomodoro
        viewModel.pomodoro.toggle()
        viewModel.pomodoro.advance(completed: true)
        viewModel.pomodoro.advance(completed: true)
        viewModel.pomodoro.advance(completed: true)
        render(viewModel, "06b-expanded-pomodoro")
        viewModel.pomodoro.reset()

        viewModel.clockMode = .stopwatch
        viewModel.stopwatch.toggle(at: Date().addingTimeInterval(-83.4))
        viewModel.stopwatch.lap(at: Date().addingTimeInterval(-40))
        render(viewModel, "07-expanded-stopwatch")

        viewModel.selectedTab = .tools
        viewModel.keepAwake.toggle()
        viewModel.keepAwake.start(.until(Date().addingTimeInterval(7200)))
        render(viewModel, "08-expanded-tools")
        viewModel.setToolsExpanded(true)
        render(viewModel, "08a-expanded-tools-more")
        viewModel.settings.pinLimit = .eight
        viewModel.setToolsExpanded(false)
        render(viewModel, "08c-expanded-tools-eight")
        viewModel.settings.pinLimit = .six
        viewModel.setToolsExpanded(true)
        viewModel.setToolsExpanded(false)

        viewModel.keepAwake.toggle()

        viewModel.state = .peek
        viewModel.clockMode = .timer
        render(viewModel, "03c-peek-timer")

        let note = viewModel.notes.addNote()
        viewModel.notes.setBody("Talking points\nOpen with the demo, then the numbers.", ofNote: note.id)
        let snippet = viewModel.notes.addSnippet()
        viewModel.notes.setTitle("Sign-off", ofSnippet: snippet.id)
        viewModel.notes.setText("Best regards,\nEthan", ofSnippet: snippet.id)
        viewModel.settings.toggleTab(.tools)
        viewModel.settings.toggleTab(.notes)
        viewModel.state = .expanded
        viewModel.selectedTab = .notes
        render(viewModel, "08d-expanded-notes")
        viewModel.settings.toggleTab(.notes)
        viewModel.settings.toggleTab(.tools)

        viewModel.timer.start(minutes: 25)
        viewModel.state = .peek
        render(viewModel, "03f-peek-timer-compact")
        viewModel.timer.reset()
        viewModel.pomodoro.toggle()
        render(viewModel, "03g-peek-pomodoro")
        viewModel.pomodoro.reset()
        viewModel.stopwatch.toggle(at: Date().addingTimeInterval(-83.4))
        viewModel.stopwatch.lap(at: Date().addingTimeInterval(-40))
        render(viewModel, "03h-peek-stopwatch")
        viewModel.stopwatch.reset()
        viewModel.state = .expanded
        viewModel.selectedTab = .reminders
        render(viewModel, "04c-expanded-reminders")
        viewModel.timer.start(minutes: 25)

        viewModel.state = .compact
        render(viewModel, "09-compact-timer")
        viewModel.stopwatch.reset()

        viewModel.nowPlaying.apply(sampleTrack())
        render(viewModel, "09b-compact-pair-timer-media")
        viewModel.nowPlaying.apply(NowPlayingState())

        viewModel.flash(IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "87%"))
        render(viewModel, "10-compact-alert")

        viewModel.showBanner(
            Announcements.headphones(AudioAccessory(name: "AirPods Pro", left: 80, right: 75, caseLevel: 60)))
        render(viewModel, "11-banner-airpods")

        viewModel.showBanner(
            Announcements.headphones(AudioAccessory(name: "AirPods Pro", left: 12, right: 40, caseLevel: 60)))
        render(viewModel, "11b-banner-airpods-low")

        viewModel.showBanner(Announcements.lowBattery(percent: 20).banner)
        render(viewModel, "12-banner-low-battery")

        viewModel.showBanner(
            IslandBanner(
                systemImage: "calendar", tint: Theme.Tint.neutral, title: "Design Review", detail: "In 5 minutes",
                actions: [.init(title: "Join") {}, .init(title: "Check Camera") {}]
            ))
        render(viewModel, "12b-banner-two-actions")

        viewModel.showBanner(
            Announcements.mirrored(
                MirroredNotification(
                    id: "snapshot", app: "Messages", title: "Maya", subtitle: "", body: "Are we still on for lunch?",
                    isPersistent: false, date: Date()), open: {}, dismiss: {}))
        render(viewModel, "12c-banner-mirrored")

        // The banner outranks an alert, so let it go first.
        viewModel.performBannerAction()
        viewModel.flash(
            IslandAlert(
                systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "82%", isCharging: true
            ))
        render(viewModel, "13-compact-charging")

        // Recording, on a fresh island: the compact dot and time, the voice note's peek, and the Mirror.
        let capture = makeViewModel()
        await capture.voice.start()
        render(capture, "14-compact-recording")
        capture.state = .peek
        render(capture, "14b-peek-voice")
        await capture.voice.stop()

        capture.selectedTab = .tools
        capture.startMirror()
        try await Task.sleep(for: .milliseconds(100))
        render(capture, "08e-expanded-mirror")
        capture.stopMirror()

        viewModel.timer.reset()
        viewModel.stopwatch.reset()
    }

    private func makeViewModel() -> IslandViewModel { TestSupport.makeViewModel() }

    /// The Mixer's panel in the Media tab (M2): with the access, and without it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderMixer() {
        let list = StubAppList()
        list.apps = [
            MixerApp(id: "com.apple.Music", name: "Music", processObjects: [1], isPlaying: true),
            MixerApp(id: "com.spotify.client", name: "Spotify", processObjects: [2], isPlaying: true),
            MixerApp(id: "us.zoom.xos", name: "zoom.us", processObjects: [3], isPlaying: true),
        ]
        for (name, access) in [
            ("04g-expanded-media-mixer", OptionalAccessState.allowed),
            ("04h-expanded-media-mixer-needs-access", .notAsked),
        ] {
            let outputs = AudioOutputs(
                devices: [AudioOutputs.Device(
                    id: AudioDeviceID(1), name: "MacBook Speakers",
                    transportType: kAudioDeviceTransportTypeBuiltIn, uid: "builtin")],
                defaultDeviceID: AudioDeviceID(1))
            let viewModel = TestSupport.makeViewModel(outputs: outputs, mixerApps: list, mixerAccess: access)
            viewModel.settings.setOn(.mixer, true)
            viewModel.settings.mixerLevels = ["com.spotify.client": 0.6]
            viewModel.nowPlaying.apply(sampleTrack())
            viewModel.mixer.start()
            viewModel.selectedTab = .media
            viewModel.state = .expanded
            viewModel.showsMediaOutputs = true
            render(viewModel, name)
        }
    }

    /// The peek's output list and the Media tab's satellite outputs.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderOutputChoices() {
        let bluetooth = StubBluetooth()
        bluetooth.devices = [PairedDevice(id: "airpods", name: "AirPods Pro", isConnected: false)]
        let viewModel = TestSupport.makeViewModel(bluetooth: bluetooth, outputs: sampleOutputs())
        viewModel.nowPlaying.apply(sampleTrack())
        viewModel.state = .peek
        viewModel.showsPeekOutputList = true
        render(viewModel, "03j-peek-output-list")

        viewModel.state = .expanded
        viewModel.selectedTab = .media
        viewModel.showsMediaOutputs = true
        render(viewModel, "04i-expanded-media-outputs", wideHostingPanel: true)
    }

    /// The Shelf's Downloads mode (G1), over a folder of sample files.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderLevels() {
        let viewModel = makeViewModel()
        viewModel.setPreviewLevels(volume: PreviewSamples.volume, brightness: nil)
        render(viewModel, "10a-levels-volume")
        viewModel.setPreviewLevels(volume: nil, brightness: PreviewSamples.brightness)
        render(viewModel, "10b-levels-brightness")
        viewModel.setPreviewLevels(volume: PreviewSamples.volume, brightness: PreviewSamples.brightness)
        render(viewModel, "10c-levels-both")
        viewModel.state = .expanded
        render(viewModel, "10d-levels-expanded-band")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderAgents() {
        func work(_ viewModel: IslandViewModel, _ agent: AgentKind, _ title: String, project: String, model: String) {
            let session = agent.rawValue
            viewModel.agents.ingest(
                AgentLogEvent(
                    kind: .turnStarted, sessionID: session, cwd: "/code/\(project)", model: model,
                    date: Date().addingTimeInterval(-252), prompt: title),
                agent: agent, session: session, announces: false)
            viewModel.agents.ingest(
                AgentLogEvent(
                    kind: .activity, tokens: AgentTokens(input: 4_000, output: 30_000, cacheRead: 150_000),
                    contextTokens: 124_000, contextWindow: 200_000),
                agent: agent, session: session, announces: false)
        }
        let viewModel = makeViewModel()
        viewModel.settings.setOn(.agents, true)
        work(viewModel, .claudeCode, "Fix the volume HUD", project: "island", model: "claude-opus-4-5-20251101")
        render(viewModel, "20a-agent-compact-claude")
        viewModel.state = .peek
        render(viewModel, "20b-agent-peek-claude")
        viewModel.state = .compact
        work(viewModel, .codex, "Add the stats view", project: "site", model: "gpt-5-codex")
        render(viewModel, "20c-agent-compact-both")
        viewModel.state = .peek
        render(viewModel, "20d-agent-peek-both")
        viewModel.state = .compact
        let task = AgentTask(
            id: "s", agent: .claudeCode, project: "island", model: "claude-opus-4-5", startedAt: Date(), lastActivity: Date(),
            title: "Fix the volume HUD", tokens: AgentTokens(input: 4_000, output: 180_000))
        viewModel.showBanner(Announcements.agentDone(task: task, duration: 252), for: .seconds(600), respectingFocus: false)
        render(viewModel, "20e-agent-done-claude")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderStats() {
        let viewModel = makeViewModel()
        viewModel.settings.setOn(.agents, true)
        viewModel.agents.usage.start()
        viewModel.agents.usage.show(PreviewSamples.usageSnapshot())
        viewModel.selectedTab = .agents
        viewModel.setAgentsMode(.stats)
        viewModel.state = .expanded
        render(viewModel, "30a-stats-all")
        viewModel.setStatsAgent(.claudeCode)
        viewModel.setStatsRange(.month)
        render(viewModel, "30b-stats-claude-30days")
        viewModel.setStatsAgent(.codex)
        render(viewModel, "30c-stats-codex")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderAgentPreviews() {
        let live = makeViewModel()
        live.settings.setOn(.agents, true)
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.viewModel.geometry = live.geometry
        for agent in AgentKind.allCases {
            let name = agent == .claudeCode ? "claude" : "codex"
            for (index, presentation) in [PreviewPresentation.compact, .peek, .banner, .expanded].enumerated() {
                preview.show(
                    AgentsOptions.previewContext(for: agent, from: PreviewContext(presentation: presentation)), animated: false)
                render(preview.viewModel, "31-preview-\(name)-\(index + 1)-\(presentation.rawValue.lowercased())")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderDownloads() {
        let viewModel = makeViewModel()
        _ = PreviewSamples.downloads(in: viewModel.downloads.folder)
        defer { try? FileManager.default.removeItem(at: viewModel.downloads.folder) }
        viewModel.settings.setOn(.downloads, true)
        viewModel.downloads.reload()
        viewModel.selectedTab = .shelf
        viewModel.state = .expanded
        viewModel.setShelfMode(.downloads)
        render(viewModel, "05d-expanded-shelf-downloads")
    }

    /// The peek's row of live activities (Choose the Activity): a timer and music, with the timer leading.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderChooseActivity() {
        let viewModel = makeViewModel()
        viewModel.settings.setOn(.chooseActivity, true)
        viewModel.nowPlaying.apply(sampleTrack())
        viewModel.timer.start(minutes: 25)
        viewModel.state = .peek
        render(viewModel, "03i-peek-choose-activity")
        viewModel.timer.reset()
    }

    /// The two drop tiles the Shelf shows while a file is dragged, as they look with the pointer over each half.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderDropTiles() {
        let viewModel = makeViewModel()
        viewModel.setFileDragActive(true)
        for (name, zone) in [("14-drop-tiles-shelf", DropZone.shelf), ("14b-drop-tiles-airdrop", DropZone.airDrop)] {
            let content = ShelfView(viewModel: viewModel, dropZone: zone)
                .frame(width: 472, height: Theme.Metrics.shelfHeight)
                .padding(18)
                .background(Color.black)
            guard let outputDirectory,
                let image = ImageRenderer(content: content.environment(\.isSnapshot, true)).nsImage,
                let tiff = image.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        }
        viewModel.setFileDragActive(false)
    }

    private func sampleTrack() -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "Midnight City"
        state.artist = "M83"
        state.isPlaying = true
        state.playbackRate = 1
        state.duration = 243
        state.elapsedTime = 81
        state.timestamp = Date()
        state.artworkBase64 = sampleArtwork().base64EncodedString()
        return state
    }

    private func sampleOutputs() -> AudioOutputs {
        let devices = [
            AudioOutputs.Device(
                id: AudioDeviceID(1), name: "MacBook Speakers", transportType: kAudioDeviceTransportTypeBuiltIn,
                uid: "builtin"),
            AudioOutputs.Device(
                id: AudioDeviceID(2), name: "Studio Display", transportType: kAudioDeviceTransportTypeDisplayPort,
                uid: "display"),
            AudioOutputs.Device(
                id: AudioDeviceID(3), name: "Living Room", transportType: kAudioDeviceTransportTypeAirPlay,
                uid: "airplay"),
            AudioOutputs.Device(
                id: AudioDeviceID(4), name: "HDMI", transportType: kAudioDeviceTransportTypeHDMI, uid: "hdmi"),
            AudioOutputs.Device(
                id: AudioDeviceID(5), name: "USB DAC", transportType: kAudioDeviceTransportTypeUSB, uid: "usb"),
            AudioOutputs.Device(
                id: AudioDeviceID(6), name: "Office", transportType: kAudioDeviceTransportTypeBluetooth, uid: "office"),
        ]
        return AudioOutputs(devices: devices, defaultDeviceID: devices[0].id)
    }

    private func sampleArtwork() -> Data {
        let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(srgbRed: 0.10, green: 0.05, blue: 0.35, alpha: 1),
                NSColor(srgbRed: 0.85, green: 0.20, blue: 0.55, alpha: 1),
            ])?.draw(in: rect, angle: 60)
            return true
        }
        let tiff = image.tiffRepresentation ?? Data()
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) ?? Data()
    }

    private func render(_ viewModel: IslandViewModel, _ name: String, wideHostingPanel: Bool = false) {
        guard let outputDirectory else { return }
        let content = IslandView(viewModel: viewModel, acceptsDrops: false)
            .frame(
                width: wideHostingPanel ? ScreenGeometry.hostingPanelWidth : ScreenGeometry.panelSize.width,
                height: wideHostingPanel ? ScreenGeometry.panelSize.height : max(viewModel.size.height, 1) + 16,
                alignment: .top)
            .background(Color(white: 0.28))
        let renderer = ImageRenderer(content: content.environment(\.isSnapshot, true))
        renderer.scale = 2
        guard let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
