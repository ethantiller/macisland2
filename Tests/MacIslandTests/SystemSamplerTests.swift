import Foundation
import Testing

@testable import MacIsland

@MainActor
struct SystemSamplerTests {
    private func ticks(_ user: UInt32, _ system: UInt32, _ idle: UInt32, _ nice: UInt32 = 0) -> CoreTicks {
        CoreTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test func cpuIsTheShareOfBusyTicksBetweenSamples() {
        let before = [ticks(100, 50, 1000), ticks(0, 0, 0)]
        let after = [ticks(130, 60, 1060), ticks(10, 0, 10)]
        // Core 1: 30 + 10 busy, 60 idle. Core 2: 10 busy, 10 idle. Busy 50 of 120 ticks.
        let fraction = SystemMath.cpuFraction(previous: before, current: after)
        #expect(fraction != nil && abs(fraction! - 50.0 / 120.0) < 0.0001)
        // Nice counts as busy.
        let nice = SystemMath.cpuFraction(previous: [ticks(0, 0, 0, 0)], current: [ticks(0, 0, 50, 50)])
        #expect(nice == 0.5)
    }

    @Test func counterWrapsAndEmptyIntervalsAreHandled() {
        // The counters are 32 bits and wrap.
        let wrapped = SystemMath.cpuFraction(
            previous: [ticks(UInt32.max - 5, 0, 0)], current: [ticks(4, 0, 10)])
        #expect(wrapped != nil && abs(wrapped! - 10.0 / 20.0) < 0.0001)
        // No ticks passed: nothing to divide by.
        #expect(SystemMath.cpuFraction(previous: [ticks(1, 1, 1)], current: [ticks(1, 1, 1)]) == nil)
        // The cores changed, or there are none.
        #expect(SystemMath.cpuFraction(previous: [ticks(1, 1, 1)], current: []) == nil)
        #expect(SystemMath.cpuFraction(previous: [], current: []) == nil)
    }

    @Test func memoryUsedIsActiveWiredAndCompressed() {
        let stats = VMStats(active: 100, wired: 50, compressed: 25)
        #expect(SystemMath.memoryUsed(stats: stats, pageSize: 16_384) == 175 * 16_384)
    }

    @Test func thermalStatesHaveWords() {
        let states: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        let words = states.map(SystemMath.thermalWords)
        #expect(Set(words).count == 4 && words.allSatisfy { !$0.isEmpty })
        #expect(SystemMath.thermalWords(.serious) == "Running Hot")
    }

    @Test func redIsOnlyForNeedsYou() {
        var reading = SystemReading(
            cpu: 0.99, memoryUsed: 15 << 30, memoryTotal: 16 << 30, pressure: .warning, thermal: .fair,
            battery: (percent: 50, onAC: false))
        #expect(!reading.memoryNeedsAttention && !reading.thermalNeedsAttention && !reading.batteryNeedsAttention)
        reading.pressure = .critical
        #expect(reading.memoryNeedsAttention)
        reading.thermal = .serious
        #expect(reading.thermalNeedsAttention)
        reading.battery = (percent: 20, onAC: false)
        #expect(reading.batteryNeedsAttention)
        reading.battery = (percent: 20, onAC: true)
        #expect(!reading.batteryNeedsAttention, "charging is fine")
        reading.battery = nil
        #expect(!reading.batteryNeedsAttention)
    }

    @Test func theCardsShowCpuMemoryThenBatteryOrHeat() {
        var reading = SystemReading(
            cpu: 0.42, memoryUsed: 8 << 30, memoryTotal: 16 << 30, pressure: .normal, thermal: .nominal,
            battery: (percent: 81, onAC: true))
        let cells = SystemWidget.cells(reading, includeBattery: true)
        #expect(cells.map(\.caption) == ["CPU", "Memory", "Battery"])
        #expect(cells.map(\.value) == ["42%", "50%", "81%"])
        #expect(SystemWidget.cells(reading, includeBattery: false).count == 2)
        reading.battery = nil
        reading.thermal = .serious
        let desktop = SystemWidget.cells(reading, includeBattery: true)
        #expect(desktop.last?.caption == "Thermal" && desktop.last?.value == "Running Hot" && desktop.last?.needsAttention == true)
        reading.cpu = nil
        #expect(SystemWidget.cells(reading, includeBattery: false)[0].value == "\u{2013}", "no reading yet")
    }

    @Test func theSystemWidgetIsOfferedOnlyWhileItsFeatureIsOn() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "MacIslandSystem.\(UUID().uuidString)")!)
        let system = WidgetID.builtIn(.system)
        #expect(!settings.isWidgetAllowed(system))
        #expect(!settings.homeLayout.addable(customs: []).filter(settings.isWidgetAllowed).contains(system))
        settings.setOn(.system, true)
        #expect(settings.isWidgetAllowed(system))
        #expect(settings.homeLayout.addable(customs: []).filter(settings.isWidgetAllowed).contains(system))

        // On Home, it leaves with the feature and returns with it.
        let descriptor = WidgetCatalog.descriptor(builtIn: .system)
        #expect(descriptor.sizes == [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1), GridSize(3, 2)])
        if let added = settings.homeLayout.adding(system, size: GridSize(1, 1)) { settings.setHomeLayout(added) }
        #expect(settings.homeLayout.isPlaced(system))
        settings.setOn(.system, false)
        #expect(!settings.homeLayout.isPlaced(system) && settings.homeHiddenByFeature.contains(system))
        settings.setOn(.system, true)
        #expect(settings.homeLayout.isPlaced(system))
        #expect(Feature.system.isBuilt && WidgetCatalog.feature(of: system) == .system)
    }

    @Test func itSamplesOnlyWhileShown() async {
        let stub = StubSystemSampler()
        let model = SystemModel(sampler: stub)
        #expect(stub.samples == 0 && model.reading == nil, "nothing is read until a view runs it")

        let task = Task { await model.run(every: .milliseconds(5), firstGap: .milliseconds(1)) }
        try? await Task.sleep(for: .milliseconds(80))
        task.cancel()
        await task.value
        #expect(stub.samples >= 2 && model.reading?.cpu == 0.5)
        #expect(stub.starts == 1 && stub.stops == 1, "the listeners go with the view")

        let after = stub.samples
        try? await Task.sleep(for: .milliseconds(60))
        #expect(stub.samples == after, "no look once the view is gone")
    }

    @Test func theFirstLookWaitsForASecondToHaveCpu() async {
        let stub = StubSystemSampler()
        stub.reading.cpu = nil
        let model = SystemModel(sampler: stub)
        let task = Task { await model.run(every: .seconds(60), firstGap: .milliseconds(1)) }
        try? await Task.sleep(for: .milliseconds(60))
        task.cancel()
        await task.value
        #expect(stub.samples == 2, "a short second look when the first had no CPU")
    }

    @Test func theLiveSamplerReadsTheMac() {
        let ticks = LiveSystemSampler.readTicks()
        #expect((ticks?.count ?? 0) >= 1)
        let vm = LiveSystemSampler.readVM()
        #expect(vm != nil && (vm?.active ?? 0) > 0)
        let sampler = LiveSystemSampler()
        let first = sampler.sample()
        #expect(first.cpu == nil && first.memoryTotal > 0 && first.memoryUsed > 0)
        let second = sampler.sample()
        if let cpu = second.cpu { #expect((0...1).contains(cpu)) }
        sampler.stop()
    }
}
