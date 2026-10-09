import AppKit
import Foundation

/// When to say the disk is nearly full: under 10 GB free, and not again until it has been above 15 GB.
enum DiskRule {
    static let warnBelow: Int64 = 10_000_000_000
    static let rearmAbove: Int64 = 15_000_000_000

    nonisolated static func shouldWarn(free: Int64, armed: Bool) -> Bool {
        armed && free < warnBelow
    }

    /// Whether a warning may fire again after seeing `free` bytes.
    nonisolated static func isArmed(afterFree free: Int64, wasArmed: Bool) -> Bool {
        free > rearmAbove ? true : wasArmed
    }
}

/// Checks free space when something is likely to have changed it (unlock, wake, a finished job or download),
/// never on a schedule.
@MainActor
final class DiskSpace {
    private(set) var isArmed = true
    @ObservationIgnored var onLow: ((Int64) -> Void)?

    private let readFree: @Sendable () -> Int64?

    init(readFree: @escaping @Sendable () -> Int64? = { DiskSpace.freeBytes() }) {
        self.readFree = readFree
    }

    func check() {
        guard let free = readFree() else { return }
        apply(free)
    }

    /// The same, with the read made off the main thread: the system call can take tens of milliseconds, and this runs just as someone
    /// starts using the Mac again.
    func checkLater() {
        let read = readFree
        Task {
            guard let free = await Task.detached(priority: .utility, operation: { read() }).value else { return }
            apply(free)
        }
    }

    private func apply(_ free: Int64) {
        if DiskRule.shouldWarn(free: free, armed: isArmed) {
            isArmed = false
            onLow?(free)
        } else {
            isArmed = DiskRule.isArmed(afterFree: free, wasArmed: isArmed)
        }
    }

    /// What the system says is available for important use, which counts space it would free by purging caches.
    nonisolated static func freeBytes() -> Int64? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func openStorageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(url)
        }
    }

    /// "8.2 GB free"
    nonisolated static func description(free: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " free"
    }
}
