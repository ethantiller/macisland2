import Foundation
import Testing

@testable import MacIsland

@MainActor
struct InputChoicesTests {
    private func makeSettings() -> AppSettings {
        let suite = "input-\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    private func state(_ title: String, app: String) -> NowPlayingState {
        var state = NowPlayingState()
        state.title = title
        state.isPlaying = true
        state.bundleIdentifier = app
        return state
    }

    // MARK: Show Media From

    @Test func musicAppsOnlyIgnoresABrowser() {
        let none: (String) -> String? = { _ in nil }
        #expect(MediaSource.any.accepts(bundleID: "com.apple.Safari", category: none))
        #expect(!MediaSource.musicApps.accepts(bundleID: "com.apple.Safari", category: none))
        #expect(MediaSource.musicApps.accepts(bundleID: "com.apple.Music", category: none))
        #expect(MediaSource.musicApps.accepts(bundleID: "com.spotify.client", category: none))
        #expect(MediaSource.musicApps.accepts(bundleID: "com.example.Player", category: { _ in "public.app-category.music" }))
        #expect(!MediaSource.musicApps.accepts(bundleID: nil, category: none))

        let model = NowPlayingModel(adapter: nil)
        var source = MediaSource.musicApps
        model.accepts = { source.accepts(bundleID: $0.bundleIdentifier, category: none) }
        model.apply(state("A video", app: "com.apple.Safari"))
        #expect(!model.state.hasMedia, "a browser tab reads as nothing playing")
        model.apply(state("A song", app: "com.apple.Music"))
        #expect(model.state.title == "A song")
        // Changing the choice applies at once to what was last reported.
        model.apply(state("A video", app: "com.apple.Safari"))
        source = .any
        model.refilter()
        #expect(model.state.title == "A video")
    }

    @Test func theSourceIsRememberedAndTravels() throws {
        let settings = makeSettings()
        #expect(settings.mediaSource == .any && settings.peekDelay == .short && settings.openOn == .lastTab)
        #expect(!settings.hidesUntilPointer && !settings.hidesInFullScreen && !settings.showsKeepAwakeCompact)
        var changes = 0
        settings.onMediaSourceChange = { changes += 1 }
        settings.mediaSource = .musicApps
        settings.mediaSource = .musicApps
        #expect(changes == 1, "a setter that doesn\u{2019}t change does nothing")
        settings.peekDelay = .long
        settings.hidesUntilPointer = true
        settings.hidesInFullScreen = true
        settings.openOn = .live
        settings.showsKeepAwakeCompact = true
        let archive = try SettingsArchive.read(SettingsArchive.make(from: settings).data())
        let other = makeSettings()
        other.restore(archive)
        #expect(
            other.mediaSource == .musicApps && other.peekDelay == .long && other.hidesUntilPointer
                && other.hidesInFullScreen && other.openOn == .live && other.showsKeepAwakeCompact)
    }

    // MARK: Peek After

    @Test func peekWaitsForTheChosenDelay() async throws {
        #expect(PeekDelay.short.duration == Theme.Timing.peekDwell && Theme.Timing.peekDwell == .milliseconds(120))
        #expect(PeekDelay.medium.duration == .milliseconds(300) && PeekDelay.long.duration == .milliseconds(600))
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.peekDelay = .medium
        viewModel.setHovering(true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(viewModel.state == .compact, "the short delay has passed and the medium one has not")
        try await Task.sleep(for: .milliseconds(450))
        #expect(viewModel.state == .peek)
    }

    // MARK: Hide Until You Point at It

    @Test func hiddenUntilPointedAtDrawsNothingThenSwells() {
        let viewModel = TestSupport.makeViewModel()
        #expect(!viewModel.isPillHidden, "off, the notch island is always drawn")
        viewModel.settings.hidesUntilPointer = true
        #expect(viewModel.isPillHidden && viewModel.size == .zero)
        // An alert is an interruption, and shows.
        viewModel.flash(
            IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "64%"), respectingFocus: false)
        #expect(!viewModel.isPillHidden)
        viewModel.clearAlert()
        #expect(viewModel.isPillHidden)
        viewModel.setHovering(true)
        #expect(!viewModel.isPillHidden && viewModel.isSwelling, "the pointer brings it, swelling")
        viewModel.setHovering(false)
        #expect(viewModel.isPillHidden)
        // The hover zone stays: the pointer still reaches it.
        #expect(viewModel.geometry.islandRect(for: viewModel.geometry.compactSize).height > 0)
    }

    // MARK: Hide in Full Screen

    @Test func aFullScreenWindowHidesTheIsland() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        func window(pid: Int32 = 5, layer: Int = 0, _ bounds: CGRect) -> WindowSnapshot {
            WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds)
        }
        #expect(FullScreenDetector.isFullScreen(windows: [window(display)], frontmostPID: 5, display: display))
        let maximized = CGRect(x: 0, y: 38, width: 1512, height: 944)
        #expect(
            !FullScreenDetector.isFullScreen(windows: [window(maximized)], frontmostPID: 5, display: display),
            "a window under the menu bar is only maximized")
        #expect(!FullScreenDetector.isFullScreen(windows: [window(pid: 9, display)], frontmostPID: 5, display: display))
        #expect(!FullScreenDetector.isFullScreen(windows: [window(layer: 25, display)], frontmostPID: 5, display: display))
        #expect(!FullScreenDetector.isFullScreen(windows: [window(display)], frontmostPID: nil, display: display))
        #expect(FullScreenDetector.isFullScreen(windows: [window(display.insetBy(dx: -0.4, dy: 0))], frontmostPID: 5, display: display))

        let viewModel = TestSupport.makeViewModel()
        viewModel.setFullScreen(true)
        #expect(!viewModel.isPillHidden, "the setting is off, so nothing changes")
        viewModel.setFullScreen(false)
        viewModel.settings.hidesInFullScreen = true
        viewModel.setFullScreen(true)
        #expect(viewModel.isPillHidden && viewModel.size == .zero)
        viewModel.setHovering(true)
        #expect(viewModel.state == .compact && !viewModel.isSwelling, "hover doesn\u{2019}t peek")
        viewModel.setHovering(false)
        viewModel.showBanner(PreviewSamples.banner(), for: .seconds(86_400), respectingFocus: false)
        #expect(viewModel.banner == nil, "an ambient banner is dropped")
        viewModel.flash(IslandAlert(systemImage: "x", tint: Theme.Tint.positive, text: "gone"), respectingFocus: false)
        #expect(viewModel.alert == nil)
        var waiting = IslandAlert(systemImage: "internaldrive.fill", tint: Theme.Tint.attention, text: "4 GB")
        waiting.staysUntilSeen = true
        viewModel.flash(waiting, respectingFocus: false)
        #expect(viewModel.alert == nil, "it waits")
        viewModel.setFullScreen(false)
        #expect(viewModel.alert?.text == "4 GB" && !viewModel.isPillHidden, "and shows when the display is free")
        // A click on the notch still opens it.
        viewModel.setFullScreen(true)
        viewModel.open()
        #expect(viewModel.state == .expanded)
    }

    // MARK: Open On

    @Test func openOnLiveGoesToTheActivitysModule() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.selectedTab = .tools
        viewModel.open()
        #expect(viewModel.selectedTab == .tools, "Last Tab is today")
        viewModel.state = .compact

        viewModel.settings.openOn = .home
        viewModel.open()
        #expect(viewModel.selectedTab == .home)
        viewModel.state = .compact

        viewModel.settings.openOn = .live
        viewModel.selectedTab = .tools
        viewModel.open()
        #expect(viewModel.selectedTab == .tools, "nothing is live: the last tab")
        viewModel.state = .compact

        viewModel.timer.start(minutes: 25)
        viewModel.open()
        #expect(viewModel.selectedTab == .clock)
        viewModel.state = .compact
        viewModel.timer.reset()

        var track = NowPlayingState()
        track.title = "Song"
        viewModel.nowPlaying.apply(track)
        viewModel.open()
        #expect(viewModel.selectedTab == .media)
        viewModel.state = .compact

        // An alert that waits to be seen sends the island to its own page.
        viewModel.selectedTab = .home
        viewModel.flash(
            IslandAlert(systemImage: "x", tint: Theme.Tint.attention, text: "!", staysUntilSeen: true, opensTab: .reminders),
            respectingFocus: false)
        viewModel.open()
        #expect(viewModel.selectedTab == .reminders)
        viewModel.state = .compact

        // The Shelf shortcut picks its own page.
        viewModel.settings.openOn = .home
        viewModel.toggleShelfFromKeyboard()
        #expect(viewModel.selectedTab == .shelf)
    }

    @Test func eachActivityHasItsModule() {
        #expect(IslandViewModel.module(for: .timer) == .clock && IslandViewModel.module(for: .stopwatch) == .clock)
        #expect(IslandViewModel.module(for: .media) == .media && IslandViewModel.module(for: .transfer) == .shelf)
        #expect(IslandViewModel.module(for: .agent) == .agents && IslandViewModel.module(for: .microphone) == nil)
        #expect(IslandViewModel.module(for: .keepAwake) == nil)
    }

    // MARK: Esc

    @Test func escStepsBackThenCloses() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.state = .expanded
        viewModel.selectedTab = .tools
        viewModel.setToolsExpanded(true)
        #expect(viewModel.stepBack() && !viewModel.toolsExpanded, "the grid goes back to the row first")
        #expect(!viewModel.stepBack(), "then Esc closes the island")

        viewModel.selectedTab = .home
        viewModel.setCalendarExpanded(true)
        viewModel.calendarSelectedDay = 15
        #expect(viewModel.stepBack() && viewModel.calendarSelectedDay == nil && viewModel.calendarExpanded, "the day first")
        #expect(viewModel.stepBack() && !viewModel.calendarExpanded, "then the month")
        #expect(!viewModel.stepBack())

        viewModel.clipboardQuery = "abc"
        viewModel.setToolsExpanded(true)
        viewModel.selectedTab = .tools
        #expect(viewModel.stepBack() && viewModel.clipboardQuery.isEmpty && viewModel.toolsExpanded, "innermost first")
    }

    @Test func escNeverStopsMirror() async {
        let camera = StubCamera()
        let viewModel = TestSupport.makeViewModel(camera: camera)
        viewModel.state = .expanded
        viewModel.selectedTab = .tools
        await viewModel.mirror.toggle()
        #expect(viewModel.mirror.isOn)
        viewModel.setToolsExpanded(true)
        #expect(!viewModel.stepBack(), "the grid behind Mirror is not a step")
        viewModel.closePinned()
        #expect(viewModel.mirror.isOn && viewModel.state == .expanded, "Mirror stays until Done")
        viewModel.mirror.stop()
    }

    // MARK: Keep Awake

    @Test func keepAwakeShowsTimeLeftOnlyWithAnEnd() {
        let viewModel = TestSupport.makeViewModel()
        defer { viewModel.keepAwake.stop() }
        viewModel.settings.showsKeepAwakeCompact = true
        viewModel.keepAwake.start(.indefinitely)
        #expect(!viewModel.compactActivities.contains(.keepAwake), "indefinitely shows nothing here")
        #expect(viewModel.keepAwake.endsAt == nil)
        viewModel.keepAwake.start(.hour)
        #expect(viewModel.keepAwake.endsAt != nil && viewModel.compactActivity == .keepAwake)
        viewModel.settings.showsKeepAwakeCompact = false
        #expect(!viewModel.compactActivities.contains(.keepAwake), "off is off")
        viewModel.settings.showsKeepAwakeCompact = true
        viewModel.settings.setOn(.tools, false)
        #expect(!viewModel.compactActivities.contains(.keepAwake), "and Tools off stops it")
        viewModel.keepAwake.stop()
        #expect(viewModel.keepAwake.endsAt == nil)
    }

    @Test func keepAwakeRanksLast() {
        let viewModel = TestSupport.makeViewModel()
        defer { viewModel.keepAwake.stop() }
        viewModel.settings.showsKeepAwakeCompact = true
        viewModel.keepAwake.start(.hour)
        var track = NowPlayingState()
        track.title = "Song"
        viewModel.nowPlaying.apply(track)
        viewModel.timer.start(minutes: 25)
        #expect(viewModel.compactActivities == [.timer, .media, .keepAwake])
        viewModel.timer.reset()
        #expect(viewModel.compactPair?.leading == .media && viewModel.compactPair?.trailing == .keepAwake)
        #expect(CompactActivity.keepAwake.title == "Keep Awake" && CompactActivity.keepAwake.choiceID == "keepAwake")
    }

    @Test func timeLeftIsWordedByTheMinute() {
        #expect(KeepAwakeTime.text(remaining: 3600) == "60m", "a fresh hour")
        #expect(KeepAwakeTime.text(remaining: 45 * 60) == "45m")
        #expect(KeepAwakeTime.text(remaining: 45 * 60 - 1) == "45m", "rounded up to the minute")
        #expect(KeepAwakeTime.text(remaining: 95 * 60) == "1h35")
        #expect(KeepAwakeTime.text(remaining: 121 * 60) == "2h01")
        #expect(KeepAwakeTime.text(remaining: 20) == "1m" && KeepAwakeTime.text(remaining: -5) == "0m")
    }
}
