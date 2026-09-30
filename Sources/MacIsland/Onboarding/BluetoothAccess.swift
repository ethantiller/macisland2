import CoreBluetooth
import Foundation

/// Asks for Bluetooth access on purpose and says how it was answered.
///
/// The app only uses IOBluetooth, whose implicit prompt gives no answer back. `PrivacyAccess` already reads
/// `CBManager.authorization`, which is the same permission, so a `CBCentralManager` is the way to ask for it and hear the reply.
@MainActor
final class BluetoothAccess: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var waiting: [CheckedContinuation<Bool, Never>] = []

    private static var isAllowed: Bool { CBManager.authorization == .allowedAlways }

    /// Whether access is allowed. Shows the system prompt only when it was never asked; a decided answer returns at once.
    func request() async -> Bool {
        if CBManager.authorization != .notDetermined { return Self.isAllowed }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            guard manager == nil else { return }
            manager = CBCentralManager(
                delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { finishIfDecided() }
    }

    private func finishIfDecided() {
        guard CBManager.authorization != .notDetermined else { return }
        let granted = Self.isAllowed
        let continuations = waiting
        waiting = []
        manager = nil
        for continuation in continuations { continuation.resume(returning: granted) }
    }
}
