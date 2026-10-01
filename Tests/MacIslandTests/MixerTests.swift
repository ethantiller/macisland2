import CoreAudio
import Foundation
import Testing

@testable import MacIsland

// MARK: Doubles

@MainActor
final class StubAppList: AppAudioListing {
    var onChange: (() -> Void)?
    var apps: [MixerApp] = []
    private(set) var started = 0
    private(set) var stopped = 0

    func start() { started += 1 }
    func stop() { stopped += 1 }
    func current() -> [MixerApp] { apps }

    /// The list changed, as the process listener would say.
    func publish(_ apps: [MixerApp]) {
        self.apps = apps
        onChange?()
    }
}

@MainActor
final class StubTap: AudioTap {
    var heardSound: Bool
    private(set) var levels: [Float] = []
    private(set) var isStopped = false
    let output: String?

    init(heard: Bool, output: String?, level: Float) {
        heardSound = heard
        self.output = output
        levels = [level]
    }

    func setLevel(_ level: Float) { levels.append(level) }
    func stop() { isStopped = true }
}

@MainActor
final class StubTapper: AudioTapping {
    var fails = false
    var heard = true
    private(set) var taps: [StubTap] = []
    private(set) var probes = 0

    func start(processObjects: [AudioObjectID], outputUID: String?, level: Float) -> AudioTap? {
        guard !fails else { return nil }
        let tap = StubTap(heard: heard, output: outputUID, level: level)
        taps.append(tap)
        return tap
    }

    func probe() async { probes += 1 }
}

// MARK: The limiter

struct BoostLimiterTests {
    private func run(level: Float, input: [Float], channels: Int = 2, rate: Double = 48_000) -> [Float] {
        var limiter = BoostLimiter(channels: channels, sampleRate: rate)
        var output = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { target in
                limiter.process(
                    source.baseAddress!, into: target.baseAddress!, frames: input.count / channels, level: level)
            }
        }
        return output
    }

    private func sine(frames: Int, amplitude: Float, channels: Int = 2) -> [Float] {
        (0..<frames).flatMap { frame in
            [Float](repeating: amplitude * sin(Float(frame) * 0.07), count: channels)
        }
    }

    @Test func unityGainPassesSamplesUnchanged() {
        let input = sine(frames: 1000, amplitude: 0.8)
        #expect(run(level: 1, input: input) == input)
    }

    @Test func belowUnityJustScales() {
        let input = sine(frames: 500, amplitude: 0.8)
        let output = run(level: 0.5, input: input)
        for index in input.indices { #expect(abs(output[index] - input[index] * 0.5) < 0.000_001) }
        #expect(run(level: 0, input: input).allSatisfy { $0 == 0 })
    }

    @Test func noSampleExceedsOneAtDoubleGain() {
        // 0.9 at double gain would be 1.8: the limiter must hold every sample inside ±1.
        let input = sine(frames: 20_000, amplitude: 0.9)
        let output = run(level: 2, input: input)
        #expect(output.allSatisfy { abs($0) <= 1.0 })
        #expect(output.contains { abs($0) > 0.7 }, "it is still loud: limited, not muted")
        // A loud burst after quiet is held inside too.
        var burst = sine(frames: 4000, amplitude: 0.1)
        burst += sine(frames: 4000, amplitude: 1.0)
        #expect(run(level: 2, input: burst).allSatisfy { abs($0) <= 1.0 })
    }

    @Test func aQuietSignalIsSimplyLouderAndLate() {
        let frames = 2000
        let input = sine(frames: frames, amplitude: 0.2)
        let output = run(level: 2, input: input)
        let lookahead = BoostLimiter(channels: 2, sampleRate: 48_000).lookahead
        for frame in lookahead..<frames {
            let expected = input[(frame - lookahead) * 2] * 2
            #expect(abs(output[frame * 2] - expected) < 0.000_01, "frame \(frame)")
        }
    }

    @Test func theLookAheadScalesWithTheSampleRate() {
        let slow = BoostLimiter(channels: 2, sampleRate: 44_100).lookahead
        let fast = BoostLimiter(channels: 2, sampleRate: 96_000).lookahead
        #expect(fast > slow * 2 - 4 && fast < slow * 2 + 4)
    }
}

// MARK: Grouping

struct AppGroupingTests {
    @Test func helpersGroupUnderTheirApp() {
        let parents: [Int32: Int32] = [30: 20, 20: 10, 10: 1]
        let apps: Set<Int32> = [10]
        #expect(AppGrouping.owner(of: 30, parent: { parents[$0] }, isApp: { apps.contains($0) }) == 10)
        #expect(AppGrouping.owner(of: 10, parent: { parents[$0] }, isApp: { apps.contains($0) }) == 10)
        #expect(AppGrouping.owner(of: 99, parent: { parents[$0] }, isApp: { apps.contains($0) }) == nil)
    }

    @Test func aLoopOfParentsEnds() {
        let parents: [Int32: Int32] = [5: 6, 6: 5]
        #expect(AppGrouping.owner(of: 5, parent: { parents[$0] }, isApp: { _ in false }) == nil)
    }
}

// MARK: The mixer's rules

@MainActor
struct AppMixerTests {
    private let music = MixerApp(id: "com.apple.Music", name: "Music", processObjects: [1], isPlaying: true)
    private let spotify = MixerApp(id: "com.spotify.client", name: "Spotify", processObjects: [2], isPlaying: true)

    private struct Rig {
        let defaults: UserDefaults
        let suite: String
        let settings: AppSettings
        let list: StubAppList
        let tapper: StubTapper
        let mixer: AppMixer
    }

    private func rig(access: OptionalAccessState? = .allowed, apps: [MixerApp] = []) -> Rig {
        let suite = "mixer-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if let access, access != .notAsked {
            OptionalAccessRecord.record(.asked, for: .systemAudio, defaults: defaults)
            if access != .asked { OptionalAccessRecord.record(access, for: .systemAudio, defaults: defaults) }
        }
        let settings = AppSettings(defaults: defaults)
        let list = StubAppList()
        list.apps = apps
        let tapper = StubTapper()
        let mixer = AppMixer(settings: settings, listing: list, tapper: tapper, defaults: defaults)
        mixer.silenceDelay = .milliseconds(20)
        return Rig(defaults: defaults, suite: suite, settings: settings, list: list, tapper: tapper, mixer: mixer)
    }

    @Test func anAppAtFullVolumeOnTheDefaultOutputHasNoTap() {
        let rig = rig(apps: [music])
        rig.mixer.start()
        #expect(rig.mixer.tappedApps.isEmpty && rig.tapper.taps.isEmpty)
        rig.mixer.setLevel(0.5, for: music.id)
        #expect(rig.mixer.tappedApps == [music.id])
        rig.mixer.setLevel(1, for: music.id)
        #expect(rig.mixer.tappedApps.isEmpty && rig.tapper.taps[0].isStopped)
    }

    @Test func aTapRunsOnlyWhileItsAppPlays() {
        let rig = rig(apps: [music])
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        #expect(rig.tapper.taps.count == 1)
        var paused = music
        paused.isPlaying = false
        rig.list.publish([paused])
        #expect(rig.mixer.tappedApps.isEmpty && rig.tapper.taps[0].isStopped, "no IO while nothing plays")
        rig.list.publish([music])
        #expect(rig.mixer.tappedApps == [music.id] && rig.tapper.taps.count == 2)
    }

    @Test func aChangedLevelReachesTheRunningTap() {
        let rig = rig(apps: [music])
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        rig.mixer.setLevel(1.5, for: music.id)
        #expect(rig.tapper.taps.count == 1 && rig.tapper.taps[0].levels == [0.5, 1.5])
        rig.mixer.setLevel(9, for: music.id)
        #expect(rig.mixer.level(for: music.id) == 2, "clamped to 200%")
        rig.mixer.setLevel(-3, for: music.id)
        #expect(rig.mixer.level(for: music.id) == 0)
    }

    @Test func neverTappedAppsStayUntapped() {
        let zoom = MixerApp(id: "us.zoom.xos", name: "zoom.us", processObjects: [9], isPlaying: true)
        let rig = rig(apps: [zoom])
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: zoom.id)
        rig.mixer.setOutput("somewhere", for: zoom.id)
        #expect(rig.mixer.tappedApps.isEmpty && rig.settings.mixerLevels.isEmpty && rig.settings.mixerOutputs.isEmpty)
        #expect(AppMixer.neverTapped(bundleID: "com.ableton.live") && AppMixer.neverTapped(bundleID: "com.microsoft.teams2.helper"))
        #expect(!AppMixer.neverTapped(bundleID: "com.apple.Music"))
    }

    @Test func silenceWhileItPlaysMeansDeniedAndTearsDown() async throws {
        let rig = rig(access: .asked, apps: [music, spotify])
        rig.tapper.heard = false
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        rig.mixer.setLevel(0.5, for: spotify.id)
        #expect(rig.mixer.tappedApps.count == 2)
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.mixer.tappedApps.isEmpty && rig.tapper.taps.allSatisfy(\.isStopped), "no app is left silent")
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: rig.defaults) == .denied)
        // Denied, nothing taps again until the access is given.
        rig.mixer.setLevel(0.7, for: music.id)
        #expect(rig.mixer.tappedApps.isEmpty)
    }

    @Test func soundThroughATapMarksItAllowed() async throws {
        let rig = rig(access: .asked, apps: [music])
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        try await Task.sleep(for: .milliseconds(200))
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: rig.defaults) == .allowed)
        #expect(rig.mixer.tappedApps == [music.id])
    }

    @Test func aTapThatCannotBeMadeMeansDenied() {
        let rig = rig(access: .asked, apps: [music])
        rig.tapper.fails = true
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: rig.defaults) == .denied)
        #expect(rig.mixer.tappedApps.isEmpty)
    }

    @Test func aGoneDeviceFallsBackToTheDefault() {
        let rig = rig(apps: [music])
        var present: Set<String> = ["speakers", "headphones"]
        rig.mixer.availableOutputs = { present }
        rig.mixer.defaultOutput = { "speakers" }
        rig.mixer.start()
        rig.mixer.setOutput("headphones", for: music.id)
        #expect(rig.mixer.tappedApps == [music.id] && rig.tapper.taps.last?.output == "headphones")
        // The device goes away: at 100% on the default, the tap goes too.
        present = ["speakers"]
        rig.mixer.devicesChanged()
        #expect(rig.mixer.tappedApps.isEmpty && rig.mixer.output(for: music.id) == nil)
        #expect(rig.mixer.chosenOutput(for: music.id) == "headphones", "the choice is kept for when it returns")
        // At another level it is tapped on the default output.
        rig.mixer.setLevel(0.5, for: music.id)
        #expect(rig.tapper.taps.last?.output == nil)
        // The default itself needs no routing.
        rig.mixer.setLevel(1, for: music.id)
        rig.mixer.setOutput("speakers", for: music.id)
        #expect(rig.mixer.tappedApps.isEmpty)
    }

    @Test func nothingIsTappedAtLaunchUnlessAllowed() {
        for (state, tapsAtLaunch) in [
            (OptionalAccessState.notAsked, 0), (.asked, 0), (.denied, 0), (.allowed, 1),
        ] {
            let rig = rig(access: state, apps: [music])
            rig.settings.mixerLevels = [music.id: 0.5]
            rig.mixer.start()
            #expect(rig.tapper.taps.count == tapsAtLaunch, "\(state)")
        }
        // An answer that can't be checked is trusted once the person adjusts something.
        let asked = rig(access: .asked, apps: [music])
        asked.mixer.start()
        asked.mixer.setLevel(0.5, for: music.id)
        #expect(asked.tapper.taps.count == 1)
        // Never asked: even an adjustment taps nothing.
        let fresh = rig(access: .notAsked, apps: [music])
        fresh.mixer.start()
        fresh.mixer.setLevel(0.5, for: music.id)
        #expect(fresh.tapper.taps.isEmpty)
    }

    @Test func levelsRoundTripAndOutputsStayLocal() throws {
        let rig = rig(apps: [music])
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        rig.mixer.setOutput("uid-1", for: music.id)
        let reloaded = AppSettings(defaults: rig.defaults)
        #expect(reloaded.mixerLevels == [music.id: 0.5] && reloaded.mixerOutputs == [music.id: "uid-1"])

        let archive = try SettingsArchive.read(SettingsArchive.make(from: rig.settings).data())
        #expect(archive.mixerLevels == [music.id: 0.5])
        let other = AppSettings(defaults: UserDefaults(suiteName: rig.suite + "2")!)
        other.restore(archive)
        #expect(other.mixerLevels == [music.id: 0.5] && other.mixerOutputs.isEmpty, "device UIDs stay on this Mac")
        // Out of range, 100%, and never-tapped entries are not taken.
        var bad = archive
        bad.mixerLevels = ["a": 3.0, "b": 1.0, "us.zoom.xos": 0.5, "c": 0.25]
        other.restore(bad)
        #expect(other.mixerLevels == ["c": 0.25])
        rig.mixer.setLevel(1, for: music.id)
        #expect(rig.settings.mixerLevels.isEmpty, "100% is not stored")
    }

    @Test func turningOffDestroysEveryTap() {
        let rig = rig(apps: [music, spotify])
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        rig.mixer.setLevel(1.5, for: spotify.id)
        #expect(rig.tapper.taps.count == 2)
        rig.mixer.stop()
        #expect(rig.tapper.taps.allSatisfy(\.isStopped) && rig.mixer.tappedApps.isEmpty)
        #expect(rig.list.stopped == 1 && !rig.mixer.isRunning)
        // Nothing starts again while it is off.
        rig.list.publish([music])
        #expect(rig.mixer.tappedApps.isEmpty)
    }

    @Test func quittingGivesEverySoundBack() {
        let rig = rig(apps: [music])
        rig.mixer.start()
        rig.mixer.setLevel(0.5, for: music.id)
        rig.mixer.tearDown()
        #expect(rig.tapper.taps[0].isStopped)
    }

    @Test func theFeatureSwitchStartsAndStopsTheMixer() {
        let viewModel = TestSupport.makeViewModel()
        var states: [Bool] = []
        let runner = FeatureRunner(
            features: viewModel.features, viewModel: viewModel, music: { _ in }, screenshots: { _ in },
            mixer: { states.append($0) })
        viewModel.settings.onFeatureChange = { runner.apply($0) }
        runner.startAtLaunch()
        #expect(states.isEmpty, "off, nothing starts at launch")
        viewModel.settings.setOn(.mixer, true)
        viewModel.settings.setOn(.mixer, false)
        #expect(states == [true, false])
        viewModel.settings.setOn(.mixer, true)
        runner.startAtLaunch()
        #expect(states == [true, false, true, true])
    }
}

// MARK: The panel in the Media tab

@MainActor
struct MixerPanelTests {
    private func playing(_ count: Int) -> [MixerApp] {
        (0..<count).map {
            MixerApp(id: "com.example.app\($0)", name: "App \($0)", processObjects: [AudioObjectID($0 + 1)], isPlaying: true)
        }
    }

    private func make(
        access: OptionalAccessState = .allowed, apps: Int = 0, media: Bool = true, mixerOn: Bool = true
    ) -> (viewModel: IslandViewModel, list: StubAppList) {
        let list = StubAppList()
        list.apps = playing(apps)
        let viewModel = TestSupport.makeViewModel(mixerApps: list, mixerAccess: access)
        viewModel.settings.setOn(.mixer, mixerOn)
        if media {
            var state = NowPlayingState()
            state.title = "Midnight City"
            state.isPlaying = true
            viewModel.nowPlaying.apply(state)
        }
        viewModel.mixer.start()
        viewModel.selectedTab = .media
        viewModel.state = .expanded
        return (viewModel, list)
    }

    private var chrome: CGFloat {
        let gap = Theme.Metrics.playerSpacing
        return Theme.Metrics.playerTopInset + Theme.Metrics.playerArtwork + gap + Theme.Metrics.playerScrubber + gap
    }

    @Test func theMediaHeightFollowsTheRows() {
        let (viewModel, list) = make()
        viewModel.showsMediaOutputs = true
        for count in 0...6 {
            list.publish(playing(count))
            let rows = CGFloat(min(max(count, 1), Theme.Metrics.mixerMaxRows))
            #expect(viewModel.mediaContentHeight(peek: false) == chrome + rows * Theme.Metrics.mixerRowHeight, "\(count) apps")
        }
        #expect(
            chrome + CGFloat(Theme.Metrics.mixerMaxRows) * Theme.Metrics.mixerRowHeight <= Theme.Metrics.homeMaxContentHeight,
            "the tallest panel fits the tallest Home")
        // Closed, the player is as tall as it was.
        viewModel.showsMediaOutputs = false
        let closed = viewModel.mediaContentHeight(peek: false)
        #expect(closed == chrome + Theme.Metrics.playerTransport)
        #expect(viewModel.mediaContentHeight(peek: true) < closed, "the peek never grows")
    }

    @Test func thePanelReplacesNotPlayingWhenAppsMakeSound() {
        let (viewModel, list) = make(apps: 2, media: false)
        #expect(viewModel.showsMixerAlone)
        let rows = CGFloat(2)
        #expect(
            viewModel.mediaContentHeight(peek: false)
                == Theme.Metrics.playerScrubber + Theme.Metrics.playerSpacing + rows * Theme.Metrics.mixerRowHeight)
        list.publish([])
        #expect(!viewModel.showsMixerAlone && viewModel.mediaContentHeight(peek: false) == Theme.Metrics.glanceHeight)
        // Off, it is still "Not Playing".
        let off = make(apps: 2, media: false, mixerOn: false).viewModel
        off.mixer.start()
        #expect(!off.showsMixerAlone)
    }

    @Test func withTheMixerOffTheButtonDoesWhatItDidBefore() {
        let (viewModel, _) = make(apps: 3, mixerOn: false)
        let closed = viewModel.mediaContentHeight(peek: false)
        viewModel.showsMediaOutputs = true
        #expect(viewModel.mediaContentHeight(peek: false) == closed, "the chips replace the scrubber at the same height")
        viewModel.selectedTab = .media
        #expect(!viewModel.stepBack(), "Esc leaves the old picker as it was")
    }

    @Test func eachPermissionStateShowsItsLine() {
        #expect(MixerPanel.line(for: .notAsked) == "The Mixer needs System Audio Recording.")
        #expect(MixerPanel.line(for: .denied) == "System Audio Recording is off.")
        #expect(MixerPanel.line(for: .asked) == nil && MixerPanel.line(for: .allowed) == nil)
        for state in [OptionalAccessState.notAsked, .denied] {
            let (viewModel, _) = make(access: state, apps: 4)
            viewModel.showsMediaOutputs = true
            #expect(viewModel.mixerBodyHeight == Theme.Metrics.mixerRowHeight, "a message takes one row: \(state)")
        }
    }

    @Test func aSliderSetsTheAppsGain() {
        let (viewModel, list) = make(apps: 1)
        let app = list.apps[0]
        // The slider runs 0 to 1 over 0 to 200%: halfway is 100%, a quarter is 50%, and a hair off 100% lands on it.
        viewModel.mixer.setLevel(AppMixer.snapped(0.25 * 2), for: app.id)
        #expect(viewModel.mixer.level(for: app.id) == 0.5)
        #expect(AppMixer.snapped(0.51 * 2) == 1 && AppMixer.snapped(1.2) == 1.2 && AppMixer.snapped(0) == 0)
        viewModel.mixer.setLevel(AppMixer.snapped(0.99), for: app.id)
        #expect(viewModel.mixer.level(for: app.id) == 1 && viewModel.settings.mixerLevels.isEmpty)
        // Previewing while dragging stores nothing.
        viewModel.mixer.previewLevel(1.7, for: app.id)
        #expect(viewModel.settings.mixerLevels.isEmpty)
    }

    @Test func anAdjustedAppStaysInTheListBetweenSongs() {
        let (viewModel, list) = make(apps: 2)
        let first = list.apps[0]
        viewModel.mixer.setLevel(0.5, for: first.id)
        list.publish([list.apps[1]])
        #expect(viewModel.mixer.rows.map(\.id).contains(first.id))
        #expect(viewModel.mixer.rows.first?.id == list.apps[1].id, "playing apps come first")
        #expect(viewModel.mixer.rows.last?.isPlaying == false)
    }

    @Test func escClosesThePanelFirst() {
        let (viewModel, _) = make(apps: 2)
        viewModel.showsMediaOutputs = true
        #expect(viewModel.stepBack() && !viewModel.showsMediaOutputs)
        #expect(!viewModel.stepBack(), "the next Esc closes the island")
    }

    @Test func thePreviewDrawsThePanelWithSampleApps() {
        let live = TestSupport.makeViewModel()
        live.settings.setOn(.mixer, true)
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.show(Feature.mixer.previewContext ?? PreviewContext())
        #expect(preview.viewModel.showsMediaOutputs && preview.viewModel.selectedTab == .media)
        #expect(preview.viewModel.mixer.rows.count == 4)
        #expect(preview.viewModel.mixer.tappedApps.count >= 1, "sample levels, on taps that do nothing")
        #expect(live.mixer.tappedApps.isEmpty, "the live mixer is untouched")
    }

    @Test func theMixerIsInTheFeaturesPaneNow() {
        #expect(Feature.mixer.isBuilt && Feature.mixer.previewContext?.showsMixer == true)
        #expect(Feature.mixer.optionalAccess == [.systemAudio])
    }
}
