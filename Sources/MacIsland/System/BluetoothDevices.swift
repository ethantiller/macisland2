import Foundation
import IOBluetooth
import Observation

struct PairedDevice: Equatable, Identifiable {
    let id: String
    let name: String
    var isConnected: Bool
}

/// Paired Bluetooth audio devices, and connecting them. Behind a protocol so tests never touch a radio.
@MainActor
protocol BluetoothDeviceProviding: AnyObject {
    func pairedAudioDevices() -> [PairedDevice]
    func connect(_ id: String) async -> Bool
    func disconnect(_ id: String)
}

/// The audio devices this Mac has paired, so headphones can be connected from the island. Read only when the
/// output picker opens.
@MainActor
@Observable
final class BluetoothDevices {
    private(set) var devices: [PairedDevice] = []

    /// Called when a device would not connect.
    @ObservationIgnored var onFailure: ((PairedDevice) -> Void)?

    @ObservationIgnored private let provider: BluetoothDeviceProviding
    @ObservationIgnored private let work: WorkTracker?

    init(provider: BluetoothDeviceProviding, work: WorkTracker? = nil) {
        self.provider = provider
        self.work = work
    }

    var notConnected: [PairedDevice] { devices.filter { !$0.isConnected } }

    func refresh() {
        devices = provider.pairedAudioDevices()
    }

    /// Shows the blue working activity while it connects. The headphones banner confirms a connection.
    func connect(_ device: PairedDevice) async {
        let job = work?.begin("Connecting")
        let connected = await provider.connect(device.id)
        if let job { work?.end(job) }
        refresh()
        if !connected { onFailure?(device) }
    }

    func disconnect(_ device: PairedDevice) {
        provider.disconnect(device.id)
        refresh()
    }

    static func failureAlert() -> IslandAlert {
        IslandAlert(
            systemImage: "exclamationmark.triangle.fill", tint: Theme.Tint.attention, text: "Couldn\u{2019}t Connect")
    }
}

/// IOBluetooth, on this Mac. `openConnection` reports back to a target, so a small object turns that into a result.
@MainActor
final class IOBluetoothProvider: BluetoothDeviceProviding {
    static let timeout: Duration = .seconds(15)

    func pairedAudioDevices() -> [PairedDevice] {
        let audio = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.deviceClassMajor == audio }
            .compactMap { device in
                device.addressString.map {
                    PairedDevice(id: $0, name: device.name ?? "Headphones", isConnected: device.isConnected())
                }
            }
    }

    func connect(_ id: String) async -> Bool {
        guard let device = IOBluetoothDevice(addressString: id) else { return false }
        if device.isConnected() { return true }
        let waiter = ConnectionWaiter()
        return await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            if device.openConnection(waiter) != kIOReturnSuccess {
                waiter.finish(false)
                return
            }
            Task { [weak waiter] in
                try? await Task.sleep(for: Self.timeout)
                waiter?.finish(false)
            }
        }
    }

    func disconnect(_ id: String) {
        _ = IOBluetoothDevice(addressString: id)?.closeConnection()
    }
}

/// The target of `openConnection`: answers once, whether the device connects, fails, or times out.
private final class ConnectionWaiter: NSObject {
    var continuation: CheckedContinuation<Bool, Never>?

    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        finish(status == kIOReturnSuccess)
    }

    func finish(_ connected: Bool) {
        continuation?.resume(returning: connected)
        continuation = nil
    }
}
