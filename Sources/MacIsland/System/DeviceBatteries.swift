import Foundation
import IOKit
import Observation
import SwiftUI

/// Battery levels of the Mac's wireless mouse, keyboard, and trackpad, read from the IORegistry.
@MainActor
@Observable
final class DeviceBatteries {
    struct Device: Identifiable, Equatable {
        let name: String
        let percent: Int
        var id: String { name }

        var systemImage: String {
            let lowercased = name.lowercased()
            if lowercased.contains("trackpad") { return "trackpad" }
            if lowercased.contains("keyboard") { return "keyboard" }
            if lowercased.contains("mouse") { return "magicmouse" }
            return "dot.radiowaves.left.and.right"
        }
    }

    private(set) var devices: [Device] = []

    /// Reads the current levels. Called while Home is visible, not on a timer of its own.
    func refresh() {
        let found = Self.parse(Self.registryEntries())
        guard found != devices else { return }
        withAnimation(Theme.Motion.resize) { devices = found }
    }

    /// One device per name, valid percentages only, in name order.
    nonisolated static func parse(_ entries: [[String: Any]]) -> [Device] {
        var seen = Set<String>()
        return entries
            .compactMap { entry -> Device? in
                guard let percent = entry["BatteryPercent"] as? Int, (0...100).contains(percent),
                      let name = (entry["Product"] as? String) ?? (entry["DeviceName"] as? String), !name.isEmpty
                else { return nil }
                return Device(name: name, percent: percent)
            }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name < $1.name }
    }

    private nonisolated static func registryEntries() -> [[String: Any]] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var entries: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                entries.append(dictionary)
            }
        }
        return entries
    }
}
