import Darwin
import Foundation
import Observation

// What the System card reads, and nothing private: CPU from the Mach processor load, memory from the VM statistics and the memory
// pressure source, battery from the power sources, and how hot the Mac is from `ProcessInfo.thermalState` (a state, not degrees:
// temperatures and fan speeds need the SMC or private HID calls, which MacIsland doesn't use).

/// One core's tick counts since boot (they wrap, so differences use wrapping subtraction).
struct CoreTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// The pages that count as memory in use.
struct VMStats: Equatable {
    var active: UInt64
    var wired: UInt64
    var compressed: UInt64
}

enum MemoryPressure: Equatable {
    case normal, warning, critical
}

/// What one look at the Mac found. CPU is nil until there are two looks to compare.
struct SystemReading: Equatable {
    var cpu: Double?
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var pressure: MemoryPressure
    var thermal: ProcessInfo.ThermalState
    var battery: (percent: Int, onAC: Bool)?

    static func == (lhs: SystemReading, rhs: SystemReading) -> Bool {
        lhs.cpu == rhs.cpu && lhs.memoryUsed == rhs.memoryUsed && lhs.memoryTotal == rhs.memoryTotal
            && lhs.pressure == rhs.pressure && lhs.thermal == rhs.thermal && lhs.battery?.percent == rhs.battery?.percent
            && lhs.battery?.onAC == rhs.battery?.onAC
    }

    var memoryFraction: Double {
        memoryTotal == 0 ? 0 : min(Double(memoryUsed) / Double(memoryTotal), 1)
    }

    // Red is for "needs you" only, beside a glyph.
    var memoryNeedsAttention: Bool { pressure == .critical }
    var thermalNeedsAttention: Bool { thermal == .serious || thermal == .critical }
    var batteryNeedsAttention: Bool { battery.map { $0.percent <= 20 && !$0.onAC } ?? false }
}

enum SystemMath {
    /// The share of ticks that were busy (user, system, nice) between two looks, 0 to 1. Nil when no ticks passed.
    static func cpuFraction(previous: [CoreTicks], current: [CoreTicks]) -> Double? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for (before, now) in zip(previous, current) {
            let user = UInt64(now.user &- before.user)
            let system = UInt64(now.system &- before.system)
            let nice = UInt64(now.nice &- before.nice)
            let idle = UInt64(now.idle &- before.idle)
            busy += user + system + nice
            total += user + system + nice + idle
        }
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }

    /// Active, wired, and compressed pages, in bytes.
    static func memoryUsed(stats: VMStats, pageSize: UInt64) -> UInt64 {
        (stats.active + stats.wired + stats.compressed) * pageSize
    }

    /// What the thermal state is called.
    static func thermalWords(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Running Cool"
        case .fair: "Warm"
        case .serious: "Running Hot"
        case .critical: "Too Hot"
        @unknown default: "Unknown"
        }
    }
}

/// Reads the Mac. Behind a protocol so the model is tested with a stub that counts its looks.
@MainActor
protocol SystemSampling: AnyObject {
    /// Starts listening for what pushes (memory pressure). Nothing runs before this.
    func start()
    func stop()
    func sample() -> SystemReading
}

@MainActor
final class LiveSystemSampler: SystemSampling {
    private var previous: [CoreTicks]?
    private var pressure = MemoryPressure.normal
    private var source: DispatchSourceMemoryPressure?

    func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated {
                self?.pressure = event.contains(.critical) ? .critical : (event.contains(.warning) ? .warning : .normal)
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        previous = nil
    }

    func sample() -> SystemReading {
        let now = Self.readTicks()
        defer { previous = now }
        let cpu = previous.flatMap { before in now.flatMap { SystemMath.cpuFraction(previous: before, current: $0) } }
        let used = Self.readVM().map { SystemMath.memoryUsed(stats: $0, pageSize: UInt64(max(sysconf(_SC_PAGESIZE), 4096))) }
        return SystemReading(
            cpu: cpu, memoryUsed: used ?? 0, memoryTotal: ProcessInfo.processInfo.physicalMemory, pressure: pressure,
            thermal: ProcessInfo.processInfo.thermalState, battery: BatteryMonitor.readInternalBattery())
    }

    /// Per-core ticks. The array the kernel hands back is freed with `vm_deallocate`.
    nonisolated static func readTicks() -> [CoreTicks]? {
        var cores: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cores)).map { core in
            let base = core * states
            return CoreTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
    }

    nonisolated static func readVM() -> VMStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return VMStats(
            active: UInt64(stats.active_count), wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count))
    }
}

/// What the System card shows. It samples only while a view is running `run()`: a `.task` on the widget, which ends when the widget
/// leaves the screen, so nothing runs while Home is closed.
@MainActor
@Observable
final class SystemModel {
    private(set) var reading: SystemReading?
    /// How many looks it has taken (for tests).
    @ObservationIgnored private(set) var looks = 0
    @ObservationIgnored private let sampler: SystemSampling

    init(sampler: SystemSampling) {
        self.sampler = sampler
    }

    /// Looks every `interval` until cancelled. CPU needs two looks, so the first is followed by a short one.
    func run(every interval: Duration = .seconds(2), firstGap: Duration = .milliseconds(300)) async {
        sampler.start()
        defer { sampler.stop() }
        look()
        if reading?.cpu == nil {
            try? await Task.sleep(for: firstGap)
            if Task.isCancelled { return }
            look()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { break }
            look()
        }
    }

    private func look() {
        reading = sampler.sample()
        looks += 1
    }
}
