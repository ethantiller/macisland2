import Darwin
import Foundation
import Observation

/// Processor, memory, and network readings for Home. Sampled every 2 seconds by Home while it is
/// visible, and never otherwise.
@MainActor
@Observable
final class SystemStats {
    struct Snapshot: Equatable {
        var cpu: Double
        var memory: Double
        /// Bytes per second.
        var download: Double
        var upload: Double
    }

    struct CPUTicks: Equatable {
        var busy: UInt64
        var total: UInt64
    }

    private(set) var snapshot: Snapshot?

    @ObservationIgnored private var lastCPU: CPUTicks?
    @ObservationIgnored private var lastNetwork: (bytes: NetworkBytes, date: Date)?

    struct NetworkBytes: Equatable {
        var received: UInt64
        var sent: UInt64
    }

    /// Reads the counters so the next `sample()` has something to compare against.
    func prime(now: Date = Date()) {
        lastCPU = Self.readCPUTicks()
        lastNetwork = (Self.readNetworkBytes(), now)
    }

    func sample(now: Date = Date()) {
        let cpuTicks = Self.readCPUTicks()
        let network = Self.readNetworkBytes()
        defer {
            lastCPU = cpuTicks
            lastNetwork = (network, now)
        }
        guard let lastCPU, let lastNetwork else { return }
        let elapsed = max(now.timeIntervalSince(lastNetwork.date), 0.001)
        snapshot = Snapshot(
            cpu: Self.cpuUsage(previous: lastCPU, current: cpuTicks),
            memory: Self.readMemoryFraction(),
            download: Self.rate(from: lastNetwork.bytes.received, to: network.received, over: elapsed),
            upload: Self.rate(from: lastNetwork.bytes.sent, to: network.sent, over: elapsed)
        )
    }

    /// Forgets the baseline, so a long gap while Home was hidden isn't averaged in.
    func reset() {
        lastCPU = nil
        lastNetwork = nil
        snapshot = nil
    }

    // MARK: Math and formatting

    nonisolated static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double {
        let total = current.total &- previous.total
        guard total > 0, current.total >= previous.total else { return 0 }
        return min(max(Double(current.busy &- previous.busy) / Double(total), 0), 1)
    }

    /// The counters only grow, so a smaller reading (an interface went away) counts as no traffic.
    nonisolated static func rate(from old: UInt64, to new: UInt64, over seconds: TimeInterval) -> Double {
        guard new >= old else { return 0 }
        return Double(new - old) / seconds
    }

    nonisolated static func formatRate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(bytesPerSecond, 0)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return value >= 100 || unit == 0 ? String(format: "%.0f %@", value, units[unit]) : String(format: "%.1f %@", value, units[unit])
    }

    // MARK: Mach and BSD readings

    nonisolated static func readCPUTicks() -> CPUTicks {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return CPUTicks(busy: 0, total: 0) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(processorCount) {
            let base = cpu * states
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return CPUTicks(busy: busy, total: total)
    }

    /// Memory in use (active, wired, and compressed) as a share of installed memory.
    nonisolated static func readMemoryFraction() -> Double {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let used = UInt64(statistics.active_count) + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
        let bytes = used * UInt64(vm_kernel_page_size)
        return min(Double(bytes) / Double(ProcessInfo.processInfo.physicalMemory), 1)
    }

    /// Bytes received and sent, summed over every interface that is up and isn't the loopback.
    nonisolated static func readNetworkBytes() -> NetworkBytes {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return NetworkBytes(received: 0, sent: 0) }
        defer { freeifaddrs(addresses) }

        var totals = NetworkBytes(received: 0, sent: 0)
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }
            let flags = Int32(interface.ifa_flags)
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
            else { continue }
            totals.received += UInt64(data.ifi_ibytes)
            totals.sent += UInt64(data.ifi_obytes)
        }
        return totals
    }
}
