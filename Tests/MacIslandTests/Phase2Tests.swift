import Foundation
import Testing
@testable import MacIsland

@MainActor
struct MinimalPairTests {
    private func playing() -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "Song"
        state.artist = "Artist"
        state.isPlaying = true
        state.playbackRate = 1
        state.duration = 200
        state.timestamp = Date()
        return state
    }

    @Test func oneActivityIsNotAPair() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.timer.start(minutes: 5)
        #expect(viewModel.compactActivities == [.timer])
        #expect(viewModel.compactPair == nil)
        viewModel.timer.reset()
    }

    @Test func topTwoShowLeadingIsTheHigherRank() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.nowPlaying.apply(playing())
        viewModel.timer.start(minutes: 5)
        #expect(viewModel.compactActivities == [.timer, .media])
        #expect(viewModel.compactPair?.leading == .timer)
        #expect(viewModel.compactPair?.trailing == .media)

        // Each side is `notch height + 8`, and the pair has no play/pause control to keep clear.
        let expected = viewModel.geometry.compactSize.width + 2 * (viewModel.geometry.notchSize.height + 8)
        #expect(viewModel.size.width == expected)
        #expect(viewModel.compactControlRect == nil)
        viewModel.timer.reset()
    }

    @Test func aThirdActivityIsLeftOut() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.nowPlaying.apply(playing())
        viewModel.timer.start(minutes: 5)
        viewModel.stopwatch.toggle()
        #expect(viewModel.compactActivities.count == 3)
        #expect(viewModel.compactPair?.leading == .timer)
        #expect(viewModel.compactPair?.trailing == .stopwatch)
        viewModel.timer.reset()
        viewModel.stopwatch.reset()
    }

    @Test func anAlertStandsAlone() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.nowPlaying.apply(playing())
        viewModel.flash(IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "80%"))
        #expect(viewModel.compactActivity != .media)
        #expect(viewModel.compactPair == nil)
    }
}

struct FullChargeTests {
    @Test func firesOnceWhenCrossingTheLevelOnCharger() {
        let crossing = BatteryMonitor.events(wasOnAC: true, lastPercent: 89, onAC: true, percent: 90, fullLevel: 90)
        #expect(crossing == [.full(percent: 90)])
        let staying = BatteryMonitor.events(wasOnAC: true, lastPercent: 90, onAC: true, percent: 91, fullLevel: 90)
        #expect(staying.isEmpty)
    }

    @Test func doesNotFireOnBatteryOrWhenAlreadyFull() {
        #expect(BatteryMonitor.events(wasOnAC: false, lastPercent: 89, onAC: false, percent: 90, fullLevel: 90).isEmpty)
        #expect(BatteryMonitor.events(wasOnAC: true, lastPercent: 100, onAC: true, percent: 100, fullLevel: 100).isEmpty)
    }

    @Test func pluggingInAndLowBatteryStillWork() {
        #expect(BatteryMonitor.events(wasOnAC: false, lastPercent: 50, onAC: true, percent: 50, fullLevel: 100)
            == [.charging(percent: 50)])
        #expect(BatteryMonitor.events(wasOnAC: false, lastPercent: 21, onAC: false, percent: 20, fullLevel: 100)
            == [.low(percent: 20)])
    }

    @MainActor
    @Test func levelIsClampedAndPersists() {
        let defaults = UserDefaults(suiteName: "MacIslandFullCharge")!
        defaults.removePersistentDomain(forName: "MacIslandFullCharge")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.fullChargeLevel == 100)
        settings.fullChargeLevel = 50
        #expect(settings.fullChargeLevel == 80)
        settings.fullChargeLevel = 90
        #expect(AppSettings(defaults: defaults).fullChargeLevel == 90)
    }
}

struct KeepAwakeDurationTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func endDates() {
        #expect(KeepAwakeDuration.indefinitely.endDate(from: now) == nil)
        #expect(KeepAwakeDuration.hour.endDate(from: now) == now.addingTimeInterval(3600))
        let later = now.addingTimeInterval(500)
        #expect(KeepAwakeDuration.until(later).endDate(from: now) == later)
    }

    @Test func upcomingHoursStartOnTheNextWholeHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 1_000_000 + 25 * 60)
        let hours = KeepAwakeDuration.upcomingHours(from: start, count: 3, calendar: calendar)
        #expect(hours.count == 3)
        #expect(hours.allSatisfy { calendar.component(.minute, from: $0) == 0 })
        #expect(hours[0] > start && hours[0].timeIntervalSince(start) <= 3600)
        #expect(hours[1].timeIntervalSince(hours[0]) == 3600)
    }

    @MainActor
    @Test func changingTheDurationKeepsItOn() {
        let keepAwake = KeepAwake()
        keepAwake.start(.indefinitely)
        #expect(keepAwake.isOn)
        keepAwake.start(.hour)
        #expect(keepAwake.isOn && keepAwake.duration == .hour)
        keepAwake.stop()
        #expect(!keepAwake.isOn && keepAwake.duration == .indefinitely)
    }

    @MainActor
    @Test func endsOnItsOwn() async throws {
        let keepAwake = KeepAwake()
        keepAwake.start(.until(Date().addingTimeInterval(0.1)))
        #expect(keepAwake.isOn)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!keepAwake.isOn)
    }
}

struct DeviceBatteryTests {
    @Test func keepsValidLevelsOncePerDevice() {
        let devices = DeviceBatteries.parse([
            ["Product": "Magic Mouse", "BatteryPercent": 82],
            ["Product": "Magic Mouse", "BatteryPercent": 82],
            ["Product": "Magic Keyboard", "BatteryPercent": 40],
            ["Product": "Broken", "BatteryPercent": 250],
            ["Product": "No Battery"],
            ["BatteryPercent": 10],
        ])
        #expect(devices.map(\.name) == ["Magic Keyboard", "Magic Mouse"])
        #expect(devices.map(\.systemImage) == ["keyboard", "magicmouse"])
    }
}

struct DriveAndScreenshotTests {
    @Test func onlyExternalEjectableLocalDrivesAreAnnounced() {
        #expect(VolumeMonitor.isEjectableDrive(isLocal: true, isBrowsable: true, isInternal: false, isEjectable: true))
        #expect(!VolumeMonitor.isEjectableDrive(isLocal: false, isBrowsable: true, isInternal: false, isEjectable: true))
        #expect(!VolumeMonitor.isEjectableDrive(isLocal: true, isBrowsable: true, isInternal: true, isEjectable: false))
        #expect(!VolumeMonitor.isEjectableDrive(isLocal: true, isBrowsable: false, isInternal: false, isEjectable: true))
    }

    @Test func hiddenAndMissingScreenshotFilesAreSkipped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let visible = directory.appendingPathComponent("Screenshot.png")
        let hidden = directory.appendingPathComponent(".Screenshot.png")
        try Data().write(to: visible)
        try Data().write(to: hidden)
        #expect(ScreenshotWatcher.isVisibleFile(visible.path))
        #expect(!ScreenshotWatcher.isVisibleFile(hidden.path))
        #expect(!ScreenshotWatcher.isVisibleFile(directory.appendingPathComponent("gone.png").path))
    }
}
