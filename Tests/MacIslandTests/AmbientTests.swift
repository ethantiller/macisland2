import Foundation
import Testing

@testable import MacIsland

struct RainRuleTests {
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    private func samples(_ amounts: [Double], from start: Date) -> [RainSample] {
        amounts.enumerated().map {
            RainSample(time: start.addingTimeInterval(Double($0.offset) * 15 * 60), millimeters: $0.element)
        }
    }

    @Test func rainStartingWithinHalfAnHourIsFoundWhenItIsDryNow() {
        // Dry now (the 12:00 quarter), rain from 12:30.
        let list = samples([0, 0.1, 0.4, 1.0], from: noon)
        let now = noon.addingTimeInterval(5 * 60)
        #expect(RainRule.start(samples: list, now: now) == noon.addingTimeInterval(30 * 60))
    }

    @Test func itIsQuietWhenRainIsFarOffOrFaint() {
        let far = samples([0, 0, 0, 0, 0.5], from: noon)
        #expect(RainRule.start(samples: far, now: noon) == nil)
        let faint = samples([0, 0.1, 0.19, 0.1], from: noon)
        #expect(RainRule.start(samples: faint, now: noon) == nil)
    }

    @Test func itIsQuietWhenItIsAlreadyRaining() {
        let list = samples([0.6, 0.8, 0], from: noon)
        let now = noon.addingTimeInterval(4 * 60)
        #expect(RainRule.isWet(samples: list, now: now))
        #expect(RainRule.start(samples: list, now: now) == nil)
    }

    @Test func rainExactlyAtTheEdgeCounts() {
        let edge = [RainSample(time: noon.addingTimeInterval(30 * 60), millimeters: 0.2)]
        #expect(RainRule.start(samples: edge, now: noon) == noon.addingTimeInterval(30 * 60))
        #expect(
            RainRule.start(samples: [RainSample(time: noon.addingTimeInterval(31 * 60), millimeters: 5)], now: noon)
                == nil)
    }

    @Test func aSpellIsAnnouncedOnceAndResetsAfterADryHour() {
        var spell = RainSpell()
        let soon = noon.addingTimeInterval(20 * 60)
        let first = spell.shouldAnnounce(start: soon, wetNow: false, now: noon)
        // Thirty minutes later it is raining, and more is forecast: no second banner.
        let whileWet = spell.shouldAnnounce(start: nil, wetNow: true, now: noon.addingTimeInterval(30 * 60))
        let stillDrying = spell.shouldAnnounce(start: soon, wetNow: false, now: noon.addingTimeInterval(45 * 60))
        // An hour after it last rained, the next spell is announced.
        let nextSpell = spell.shouldAnnounce(
            start: soon, wetNow: false, now: noon.addingTimeInterval(30 * 60 + 61 * 60))
        #expect(first && !whileWet && !stillDrying && nextSpell)
    }

    @Test func aForecastThatNeverArrivesResetsToo() {
        var spell = RainSpell()
        let due = noon.addingTimeInterval(600)
        let first = spell.shouldAnnounce(start: due, wetNow: false, now: noon)
        let again = spell.shouldAnnounce(start: due, wetNow: false, now: noon.addingTimeInterval(30 * 60))
        let later = spell.shouldAnnounce(start: due, wetNow: false, now: noon.addingTimeInterval(61 * 60))
        #expect(first && !again && later)
    }
}

@MainActor
struct RainForecastTests {
    /// Quarter hours from 15:00 local (UTC+2): dry, dry, then 0.5 mm from 15:30.
    private let forecast = Data(
        #"""
        {"utc_offset_seconds":7200,
         "current":{"temperature_2m":18.4,"weather_code":3,"is_day":1},
         "minutely_15":{"time":["2026-09-29T15:00","2026-09-29T15:15","2026-09-29T15:30","2026-09-29T15:45"],
                        "precipitation":[0.0,0.0,0.5,null]}}
        """#.utf8)

    @Test func theRequestAsksForQuarterHours() {
        let place = WeatherModel.Place(name: "Paris", latitude: 48.85, longitude: 2.35)
        let items = URLComponents(
            url: WeatherModel.forecastURL(place: place, fahrenheit: false)!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.contains { $0.name == "minutely_15" && $0.value == "precipitation" } == true)
    }

    @Test func parsesQuarterHoursInThePlacesTimeZone() throws {
        let samples = WeatherModel.parseRain(forecast)
        #expect(samples.map(\.millimeters) == [0, 0, 0.5, 0])
        // 15:00 at UTC+2 is 13:00 UTC.
        let first = try #require(samples.first)
        #expect(
            Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: first.time).hour
                == 13)
        #expect(WeatherModel.parseRain(Data("{}".utf8)).isEmpty)
    }

    @Test func aCityWithRainComingSaysSoonOnceEvenAsItRefreshes() async throws {
        let model = WeatherModel()
        model.typingPause = .zero
        model.refreshInterval = .milliseconds(30)
        let start = try #require(WeatherModel.parseRain(forecast).first).time
        model.now = { start.addingTimeInterval(5 * 60) }
        let place = Data(#"{"results":[{"name":"Paris","latitude":48.85,"longitude":2.35}]}"#.utf8)
        let forecast = forecast
        model.fetch = { url in url.host == "geocoding-api.open-meteo.com" ? place : forecast }
        var announced: [Date] = []
        model.onRainSoon = { announced.append($0) }
        model.configure(city: "Paris")
        for _ in 0..<100 where announced.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(100))
        model.configure(city: "")
        #expect(announced == [start.addingTimeInterval(30 * 60)])
    }
}

struct DiskRuleTests {
    @Test func warnsBelowTenGigabytesOnlyWhenArmed() {
        #expect(DiskRule.shouldWarn(free: 8_200_000_000, armed: true))
        #expect(!DiskRule.shouldWarn(free: 8_200_000_000, armed: false))
        #expect(!DiskRule.shouldWarn(free: 10_000_000_000, armed: true))
        #expect(!DiskRule.shouldWarn(free: 50_000_000_000, armed: true))
    }

    @Test func rearmsOnlyAboveFifteenGigabytes() {
        #expect(!DiskRule.isArmed(afterFree: 12_000_000_000, wasArmed: false))
        #expect(!DiskRule.isArmed(afterFree: 15_000_000_000, wasArmed: false))
        #expect(DiskRule.isArmed(afterFree: 15_000_000_001, wasArmed: false))
        #expect(DiskRule.isArmed(afterFree: 1, wasArmed: true))
    }

    @Test func describesWhatIsLeft() {
        #expect(DiskSpace.description(free: 8_200_000_000) == "8.2 GB free")
    }
}

@MainActor
struct DiskSpaceTests {
    private final class Free { var bytes: Int64? = 30_000_000_000 }

    @Test func warnsOnceUntilThereIsRoomAgain() {
        let free = Free()
        let disk = DiskSpace(readFree: { free.bytes })
        var warnings: [Int64] = []
        disk.onLow = { warnings.append($0) }

        disk.check()
        #expect(warnings.isEmpty)
        free.bytes = 8_000_000_000
        disk.check()
        disk.check()
        #expect(warnings == [8_000_000_000])
        free.bytes = 12_000_000_000
        disk.check()
        free.bytes = 9_000_000_000
        disk.check()
        #expect(warnings.count == 1)
        free.bytes = 16_000_000_000
        disk.check()
        free.bytes = 9_000_000_000
        disk.check()
        #expect(warnings.count == 2)
    }

    @Test func aFailedReadIsIgnored() {
        let disk = DiskSpace(readFree: { nil })
        var warned = false
        disk.onLow = { _ in warned = true }
        disk.check()
        #expect(!warned && disk.isArmed)
    }

    @Test func theRealVolumeCanBeRead() {
        #expect((DiskSpace.freeBytes() ?? 0) > 0)
    }
}

@MainActor
struct BluetoothDevicesTests {
    private func makeDevices(_ provider: StubBluetooth, work: WorkTracker? = nil) -> BluetoothDevices {
        BluetoothDevices(provider: provider, work: work)
    }

    @Test func listsWhatIsNotConnectedOnceRefreshed() {
        let provider = StubBluetooth()
        provider.devices = [
            PairedDevice(id: "aa", name: "AirPods", isConnected: false),
            PairedDevice(id: "bb", name: "Speaker", isConnected: true),
        ]
        let devices = makeDevices(provider)
        #expect(devices.notConnected.isEmpty)
        devices.refresh()
        #expect(devices.notConnected.map(\.name) == ["AirPods"])
    }

    @Test func connectingUpdatesTheListAndShowsWork() async {
        let provider = StubBluetooth()
        provider.devices = [PairedDevice(id: "aa", name: "AirPods", isConnected: false)]
        let work = WorkTracker()
        let devices = makeDevices(provider, work: work)
        devices.refresh()
        await devices.connect(devices.notConnected[0])
        #expect(devices.notConnected.isEmpty && devices.devices.first?.isConnected == true)
        #expect(work.jobs.isEmpty)
    }

    @Test func aFailureIsReported() async {
        let provider = StubBluetooth()
        provider.devices = [PairedDevice(id: "aa", name: "AirPods", isConnected: false)]
        provider.connectSucceeds = false
        let devices = makeDevices(provider)
        devices.refresh()
        var failed: [String] = []
        devices.onFailure = { failed.append($0.name) }
        await devices.connect(devices.notConnected[0])
        #expect(failed == ["AirPods"] && devices.notConnected.count == 1)
        #expect(BluetoothDevices.failureAlert().text == "Couldn\u{2019}t Connect")
    }

    @Test func disconnectingClosesTheConnection() {
        let provider = StubBluetooth()
        provider.devices = [PairedDevice(id: "aa", name: "AirPods", isConnected: true)]
        let devices = makeDevices(provider)
        devices.refresh()
        devices.disconnect(devices.devices[0])
        #expect(provider.disconnected == ["aa"] && devices.notConnected.count == 1)
    }
}
