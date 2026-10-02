import Foundation
import Testing

@testable import MacIsland

@MainActor
private final class StubVolume: SystemVolume {
    var canSetVolume = true
    var level: VolumeLevel? = VolumeLevel(fraction: 0.5, isMuted: false)
    private(set) var writes: [VolumeLevel] = []
    var accepts = true

    func read() -> VolumeLevel? { level }

    func write(_ new: VolumeLevel) -> Bool {
        guard accepts else { return false }
        writes.append(new)
        level = new
        return true
    }
}

@MainActor
private final class StubKeyTap: MediaKeyTapping {
    var allowsStart = true
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var isRunning = false
    private var handler: (@MainActor (MediaKeyEvent) -> KeyDisposition)?
    private var onDisabled: (@MainActor () -> Void)?

    func start(
        handler: @escaping @MainActor (MediaKeyEvent) -> KeyDisposition, onDisabled: @escaping @MainActor () -> Void
    ) -> Bool {
        guard allowsStart else { return false }
        starts += 1
        isRunning = true
        self.handler = handler
        self.onDisabled = onDisabled
        return true
    }

    func stop() {
        stops += 1
        isRunning = false
        handler = nil
    }

    /// A press, as the system would deliver it.
    func press(_ key: MediaKey, down: Bool = true, quarter: Bool = false) -> KeyDisposition? {
        handler?(MediaKeyEvent(key: key, isDown: down, isRepeat: false, isQuarterStep: quarter))
    }

    func systemTurnsItOff() { onDisabled?() }
}

@MainActor
private final class StubBrightness: DisplayBrightness {
    var canSetBrightness = true
    var level: Double? = 0.5
    private(set) var writes: [Double] = []

    func read() -> Double? { level }

    func write(_ fraction: Double) -> Bool {
        writes.append(fraction)
        level = fraction
        return true
    }
}

struct VolumeMathTests {
    @Test func theSharedStepMathIsOneSixteenthOrOneSixtyFourth() {
        #expect(LevelStep.step(0.5, up: true, quarter: false) == 0.5625)
        #expect(LevelStep.step(0.5, up: false, quarter: true) == 0.5 - 1.0 / 64)
        #expect(LevelStep.step(1, up: true, quarter: false) == 1 && LevelStep.step(0, up: false, quarter: false) == 0)
    }

    @Test func theVolumeHasSixteenStepsAndTheKeysMoveOneAtATime() {
        let half = VolumeLevel(fraction: 0.5, isMuted: false)
        #expect(VolumeStep.apply(.volumeUp, to: half).fraction == 0.5625)
        #expect(VolumeStep.apply(.volumeDown, to: half).fraction == 0.4375)
        #expect(VolumeStep.apply(.volumeUp, to: VolumeLevel(fraction: 0, isMuted: false)).fraction == 1.0 / 16)
        #expect(VolumeStep.apply(.volumeUp, to: VolumeLevel(fraction: 1, isMuted: false)).fraction == 1)
        #expect(VolumeStep.apply(.volumeDown, to: VolumeLevel(fraction: 0, isMuted: false)).fraction == 0)
        // Sixteen presses from silence reach the top exactly.
        var level = VolumeLevel(fraction: 0, isMuted: false)
        for _ in 0..<16 { level = VolumeStep.apply(.volumeUp, to: level) }
        #expect(level.fraction == 1)
    }

    @Test func aLevelSetBySomethingElseLandsOnTheGrid() {
        // 0.53 is nearest to step 8 (0.5), so up goes to step 9.
        #expect(VolumeStep.apply(.volumeUp, to: VolumeLevel(fraction: 0.53, isMuted: false)).fraction == 0.5625)
        #expect(VolumeStep.apply(.volumeDown, to: VolumeLevel(fraction: 0.53, isMuted: false)).fraction == 0.4375)
    }

    @Test func optionAndShiftMakeAQuarterStep() {
        let half = VolumeLevel(fraction: 0.5, isMuted: false)
        #expect(VolumeStep.apply(.volumeUp, to: half, quarter: true).fraction == 0.5 + 1.0 / 64)
        #expect(VolumeStep.apply(.volumeDown, to: half, quarter: true).fraction == 0.5 - 1.0 / 64)
    }

    @Test func muteTogglesAndKeepsTheLevelAndAStepUnmutes() {
        let half = VolumeLevel(fraction: 0.5, isMuted: false)
        let muted = VolumeStep.apply(.mute, to: half)
        #expect(muted == VolumeLevel(fraction: 0.5, isMuted: true))
        #expect(VolumeStep.apply(.mute, to: muted) == half)
        #expect(!VolumeStep.apply(.volumeUp, to: muted).isMuted && !VolumeStep.apply(.volumeDown, to: muted).isMuted)
    }

    @Test func theSpeakerFollowsTheLevelAndIsSlashedWhenSilent() {
        func symbol(_ fraction: Double, muted: Bool = false) -> String {
            VolumeLevel(fraction: fraction, isMuted: muted).symbol
        }
        #expect(symbol(0) == "speaker.slash.fill" && symbol(0.8, muted: true) == "speaker.slash.fill")
        #expect(symbol(0.05) == "speaker.wave.1.fill" && symbol(0.33) == "speaker.wave.1.fill")
        #expect(symbol(0.34) == "speaker.wave.2.fill" && symbol(0.66) == "speaker.wave.2.fill")
        #expect(symbol(0.67) == "speaker.wave.3.fill" && symbol(1) == "speaker.wave.3.fill")
    }

    @Test func mutedShowsNothingFilledAndZeroPercent() {
        let muted = VolumeLevel(fraction: 0.6, isMuted: true)
        #expect(muted.shown == 0 && muted.percent == 0 && muted.isSilent)
        #expect(VolumeLevel(fraction: 0.62, isMuted: false).percent == 62)
        #expect(!VolumeLevel(fraction: 0.01, isMuted: false).isSilent)
    }

    @Test func theKeyTypesAreTheSystemsOwn() {
        #expect(MediaKey(rawValue: 0) == .volumeUp && MediaKey(rawValue: 1) == .volumeDown && MediaKey(rawValue: 7) == .mute)
        #expect(MediaKey(rawValue: 2) == .brightnessUp && MediaKey(rawValue: 3) == .brightnessDown)
        #expect(MediaKey(rawValue: 4) == nil, "the other keys are not this HUD's")
    }
}

@MainActor
struct LevelHUDControllerTests {
    private struct Rig {
        let controller: LevelHUDController
        let tap: StubKeyTap
        let volume: StubVolume
        let brightness: StubBrightness
        let shown: Box
    }

    private final class Box { var levels: [LevelReading] = [] }

    private func makeRig(access: Bool = true) -> Rig {
        let tap = StubKeyTap()
        let volume = StubVolume()
        let brightness = StubBrightness()
        let controller = LevelHUDController(tap: tap, volume: volume, brightness: brightness)
        controller.hasAccess = { access }
        let box = Box()
        controller.onShow = { box.levels.append($0) }
        return Rig(controller: controller, tap: tap, volume: volume, brightness: brightness, shown: box)
    }

    @Test func withoutAccessThereIsNoTap() {
        let rig = makeRig(access: false)
        #expect(rig.controller.start() == .needsAccess)
        #expect(!rig.controller.isActive && rig.tap.starts == 0)
    }

    @Test func theTapExistsOnlyWhileItIsOn() {
        let rig = makeRig()
        #expect(rig.controller.start() == .started && rig.controller.isActive && rig.tap.isRunning)
        #expect(rig.controller.start() == .started && rig.tap.starts == 1, "starting again makes no second tap")
        rig.controller.stop()
        #expect(!rig.controller.isActive && !rig.tap.isRunning && rig.tap.stops == 1)
        rig.controller.stop()
        #expect(rig.tap.stops == 1, "stopping again does nothing")
    }

    @Test func aRefusedTapIsAFailureAndNothingIsLeftOn() {
        let rig = makeRig()
        rig.tap.allowsStart = false
        #expect(rig.controller.start() == .failed && !rig.controller.isActive)
    }

    @Test func aKeyPressSetsTheVolumeShowsItAndIsTaken() {
        let rig = makeRig()
        rig.controller.start()
        #expect(rig.tap.press(.volumeUp) == .consume)
        #expect(rig.volume.writes == [VolumeLevel(fraction: 0.5625, isMuted: false)])
        #expect(rig.shown.levels == rig.volume.writes.map(LevelReading.volume))
        #expect(rig.tap.press(.mute) == .consume)
        #expect(rig.volume.level?.isMuted == true && rig.shown.levels.count == 2)
    }

    @Test func aKeyUpIsTakenTooButChangesNothing() {
        let rig = makeRig()
        rig.controller.start()
        #expect(rig.tap.press(.volumeUp, down: false) == .consume)
        #expect(rig.volume.writes.isEmpty && rig.shown.levels.isEmpty)
    }

    @Test func aQuarterStepIsPassedThrough() {
        let rig = makeRig()
        rig.controller.start()
        _ = rig.tap.press(.volumeUp, quarter: true)
        #expect(rig.volume.writes.first?.fraction == 0.5 + 1.0 / 64)
    }

    @Test func anOutputWithNoVolumeIsLeftToTheSystem() {
        let rig = makeRig()
        rig.volume.canSetVolume = false
        rig.controller.start()
        #expect(rig.tap.press(.volumeUp) == .passThrough)
        #expect(rig.volume.writes.isEmpty && rig.shown.levels.isEmpty)
        rig.volume.canSetVolume = true
        rig.volume.level = nil
        #expect(rig.tap.press(.volumeUp) == .passThrough, "a volume that can't be read is the system's too")
        rig.volume.level = VolumeLevel(fraction: 0.5, isMuted: false)
        rig.volume.accepts = false
        #expect(rig.tap.press(.volumeUp) == .passThrough, "a write that failed is never swallowed")
    }

    @Test func itStepsAsideWhenTheIslandCantShowItOrCleanKeysHasTheKeys() {
        let rig = makeRig()
        rig.controller.start()
        rig.controller.canShow = { false }
        #expect(rig.tap.press(.volumeDown) == .passThrough && rig.volume.writes.isEmpty)
        rig.controller.canShow = { true }
        rig.controller.isSuspended = { true }
        #expect(rig.tap.press(.volumeDown) == .passThrough && rig.volume.writes.isEmpty)
        rig.controller.isSuspended = { false }
        #expect(rig.tap.press(.volumeDown) == .consume)
    }

    @Test func brightnessKeysAreTakenOnlyWhenTheDisplayCanBeSet() {
        let rig = makeRig()
        rig.controller.start()
        #expect(rig.tap.press(.brightnessUp) == .consume)
        #expect(rig.brightness.writes == [0.5625] && rig.shown.levels == [.brightness(0.5625)])
        #expect(rig.tap.press(.brightnessDown, down: false) == .consume)
        #expect(rig.brightness.writes.count == 1)
        rig.brightness.canSetBrightness = false
        #expect(rig.tap.press(.brightnessUp) == .passThrough, "an external display's keys are the system's")
        rig.brightness.canSetBrightness = true
        rig.brightness.level = nil
        #expect(rig.tap.press(.brightnessUp) == .passThrough)
    }

    @Test func aStoppedControllerTakesNothing() {
        let rig = makeRig()
        rig.controller.start()
        rig.controller.stop()
        #expect(rig.controller.handle(MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false, isQuarterStep: false)) == .passThrough)
    }

    @Test func whenTheSystemTurnsTheTapOffTheControllerStopsAndSaysSo() {
        let rig = makeRig()
        var lost = 0
        rig.controller.onLostAccess = { lost += 1 }
        rig.controller.start()
        rig.tap.systemTurnsItOff()
        #expect(!rig.controller.isActive && rig.tap.stops == 1 && lost == 1)
        // The system's notice arriving again, after it stopped, does nothing more.
        rig.tap.systemTurnsItOff()
        #expect(lost == 1)
    }
}

@MainActor
struct VolumeHUDIslandTests {
    private let volume = VolumeLevel(fraction: 0.4, isMuted: false)

    @Test func showingVolumeWidensTheIslandAndKeepsTheNotchBetweenTheSides() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.flash(IslandAlert(systemImage: "bell", tint: Theme.Tint.neutral, text: "Hi"), respectingFocus: false)
        let plain = viewModel.size.width
        viewModel.clearAlert()
        viewModel.showLevel(.volume(volume))
        #expect(viewModel.levels.volume?.fraction == 0.4 && viewModel.levels.brightness == nil)
        #expect(viewModel.size.width == plain + Theme.Metrics.volumeHUDLeading + Theme.Metrics.volumeHUDTrailing - 2 * 64)
        #expect(viewModel.horizontalOffset == (Theme.Metrics.volumeHUDTrailing - Theme.Metrics.volumeHUDLeading) / 2)
    }

    @Test func brightnessAloneUsesTheSameLayout() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.showLevel(.brightness(0.8))
        #expect(viewModel.levels.brightness == 0.8 && viewModel.levels.volume == nil)
        #expect(viewModel.horizontalOffset == (Theme.Metrics.volumeHUDTrailing - Theme.Metrics.volumeHUDLeading) / 2)
    }

    @Test func bothAtOnceSplitAroundTheNotchWithEqualSides() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.showLevel(.volume(volume))
        let single = viewModel.size.width
        viewModel.showLevel(.brightness(0.8))
        #expect(viewModel.levels.isBoth)
        #expect(viewModel.horizontalOffset == 0)
        #expect(viewModel.size.width == single - Theme.Metrics.volumeHUDLeading - Theme.Metrics.volumeHUDTrailing + 2 * Theme.Metrics.levelSideWidth)
        #expect(viewModel.compactPair == nil, "the levels stand alone")
    }

    @Test func whenOneSideExpiresTheIslandReturnsToTheSingleLayout() async {
        let viewModel = TestSupport.makeViewModel()
        viewModel.showLevel(.volume(volume))
        viewModel.showLevel(.brightness(0.8))
        viewModel.setPreviewLevels(volume: volume, brightness: nil)
        #expect(!viewModel.levels.isBoth)
        #expect(viewModel.horizontalOffset == (Theme.Metrics.volumeHUDTrailing - Theme.Metrics.volumeHUDLeading) / 2)
    }

    @Test func itShowsOnAnOpenIslandWithoutChangingItsSize() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.open()
        #expect(viewModel.canShowLevelHUD)
        let before = viewModel.size
        viewModel.showLevel(.volume(volume))
        #expect(viewModel.levels.volume != nil)
        #expect(viewModel.size == before)
        viewModel.state = .peek
        #expect(viewModel.canShowLevelHUD)
    }

    @Test func itNeverTakesTheStageFromSomethingThatNeedsYou() {
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.canShowLevelHUD)
        viewModel.flash(
            IslandAlert(systemImage: "bell", tint: Theme.Tint.attention, text: "Done", staysUntilSeen: true),
            respectingFocus: false)
        #expect(!viewModel.canShowLevelHUD, "a needs-you alert is never queued behind or replaced")
        let banner = TestSupport.makeViewModel()
        banner.showBanner(
            IslandBanner(systemImage: "bell", tint: Theme.Tint.neutral, title: "Hi"), respectingFocus: false)
        #expect(!banner.canShowLevelHUD)
    }

    @Test func thePointerOnItHoldsItAndLeavingLetsItGo() async {
        let viewModel = TestSupport.makeViewModel()
        viewModel.showLevel(.volume(volume))
        viewModel.setHovering(true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.levels.volume != nil)
        viewModel.setHovering(false)
        #expect(viewModel.levels.volume != nil, "it leaves after its time, not at once")
    }

    @Test func aPeekIsStillAboutWhatIsLiveNotTheLevels() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.showLevel(.volume(volume))
        viewModel.state = .peek
        #expect(viewModel.peekActivity == .none)
    }

    @Test func theBrightnessSunFollowsTheLevel() {
        #expect(LevelHUD.brightnessSymbol(0.2) == "sun.min.fill" && LevelHUD.brightnessSymbol(0.5) == "sun.max.fill")
        #expect(LevelHUD.percent(of: 0.456) == 46)
    }
}

@MainActor
struct VolumeHUDSettingTests {
    private func makeSettings() -> (AppSettings, UserDefaults) {
        let suite = "MacIslandVolumeHUD.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppSettings(defaults: defaults), defaults)
    }

    @Test func itIsOffUntilTurnedOnAndIsKept() {
        let (settings, defaults) = makeSettings()
        #expect(!settings.replacesVolumeHUD)
        settings.replacesVolumeHUD = true
        #expect(AppSettings(defaults: defaults).replacesVolumeHUD)
    }

    @Test func turningItOnAndOffTellsTheAppOnce() {
        let (settings, _) = makeSettings()
        var changes = 0
        settings.onVolumeHUDChange = { changes += 1 }
        settings.replacesVolumeHUD = true
        settings.replacesVolumeHUD = false
        #expect(changes == 2)
    }

    @Test func itGoesThroughTheSettingsFile() throws {
        let (original, _) = makeSettings()
        original.replacesVolumeHUD = true
        let data = try SettingsArchive.make(from: original).data()
        let (target, _) = makeSettings()
        target.restore(try SettingsArchive.read(data))
        #expect(target.replacesVolumeHUD)
        target.resetAll()
        #expect(!target.replacesVolumeHUD)
    }
}
