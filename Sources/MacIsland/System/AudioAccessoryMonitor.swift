import Foundation
import IOBluetooth

struct AudioAccessory: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var main: Int?

    var systemImage: String {
        let lowercased = name.lowercased()
        if lowercased.contains("airpods max") { return "airpodsmax" }
        if lowercased.contains("airpods pro") { return "airpodspro" }
        if lowercased.contains("airpods") { return "airpods" }
        if lowercased.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// The emptier earbud, or the one battery a headset has. The case doesn't count: the earbuds are what run out.
    var lowestLevel: Int? { [left, right, main].compactMap { $0 }.min() }

    /// Low enough to need charging soon: the banner's ring turns red.
    var isLow: Bool { (lowestLevel ?? 100) <= Self.lowLevel }

    static let lowLevel = 20

    var batterySummary: String? {
        if left != nil || right != nil {
            return [
                left.map { "L \($0)%" },
                right.map { "R \($0)%" },
                caseLevel.map { "Case \($0)%" },
            ]
            .compactMap { $0 }
            .joined(separator: "   ")
        }
        return main.map { "\($0)%" }
    }

    /// Reads battery levels from `system_profiler SPBluetoothDataType -json` output.
    static func parse(systemProfilerJSON data: Data, name: String, address: String) -> AudioAccessory {
        var accessory = AudioAccessory(name: name)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return accessory }

        let wantedAddress = normalize(address)
        let connected = controllers.flatMap { $0["device_connected"] as? [[String: Any]] ?? [] }
        let entries = connected.flatMap { $0.map { (name: $0.key, info: $0.value as? [String: Any] ?? [:]) } }
        guard
            let match = entries.first(where: { normalize($0.info["device_address"] as? String ?? "") == wantedAddress })
                ?? entries.first(where: { $0.name == name })
        else { return accessory }

        func level(_ key: String) -> Int? {
            (match.info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
        }
        accessory.left = level("device_batteryLevelLeft")
        accessory.right = level("device_batteryLevelRight")
        accessory.caseLevel = level("device_batteryLevelCase")
        accessory.main = level("device_batteryLevelMain")
        return accessory
    }

    private static func normalize(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }
}

/// Announces headphones as they connect over Bluetooth.
@MainActor
final class AudioAccessoryMonitor: NSObject {
    var onConnect: ((AudioAccessory) -> Void)?

    private var notification: IOBluetoothUserNotification?
    private var startedAt = Date.distantFuture

    /// Safe to call again: the first-run guide may hold this back on a fresh install, and more than one path can start it.
    func start() {
        guard notification == nil else { return }
        startedAt = Date()
        notification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Registration reports devices that were already connected; only announce new ones.
        guard Date().timeIntervalSince(startedAt) > 3,
            device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
        else { return }

        let name = device.name ?? "Headphones"
        let address = device.addressString ?? ""
        Task { [weak self] in
            // Battery levels show up in system_profiler a moment after the connection.
            try? await Task.sleep(for: .seconds(2))
            let data = await Self.systemProfilerOutput()
            let accessory = AudioAccessory.parse(systemProfilerJSON: data, name: name, address: address)
            self?.onConnect?(accessory)
        }
    }

    private nonisolated static func systemProfilerOutput() async -> Data {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return Data() }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        }.value
    }
}
