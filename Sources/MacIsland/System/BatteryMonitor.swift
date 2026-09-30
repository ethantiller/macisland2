import Foundation
import IOKit.ps

/// Reports plugging in the charger, dropping to 20% / 10% on battery, and reaching the full-charge level.
@MainActor
final class BatteryMonitor {
    enum Event: Equatable {
        case charging(percent: Int)
        case low(percent: Int)
        /// Reached the full-charge level while plugged in.
        case full(percent: Int)
    }

    var onEvent: ((Event) -> Void)?
    /// The level that counts as full (80 to 100), read at each reading so Settings changes apply at once.
    var fullChargeLevel: () -> Int = { 100 }

    private var runLoopSource: CFRunLoopSource?
    private var wasOnAC: Bool?
    private var lastPercent: Int?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.check() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        check()
    }

    private func check() {
        guard let reading = Self.readInternalBattery() else { return }
        let (percent, onAC) = reading
        defer {
            wasOnAC = onAC
            lastPercent = percent
        }
        guard let wasOnAC, let lastPercent else { return }
        Self.events(
            wasOnAC: wasOnAC, lastPercent: lastPercent, onAC: onAC, percent: percent, fullLevel: fullChargeLevel()
        )
        .forEach { onEvent?($0) }
    }

    /// The battery glyph for a level, with a bolt while it is on the charger.
    nonisolated static func symbol(percent: Int, onAC: Bool) -> String {
        let level = percent >= 88 ? "100" : percent >= 63 ? "75" : percent >= 38 ? "50" : percent >= 13 ? "25" : "0"
        return onAC && level == "100" ? "battery.100percent.bolt" : "battery.\(level)percent"
    }

    /// What a new reading means, given the previous one.
    nonisolated static func events(wasOnAC: Bool, lastPercent: Int, onAC: Bool, percent: Int, fullLevel: Int) -> [Event] {
        var events: [Event] = []
        if onAC && !wasOnAC {
            events.append(.charging(percent: percent))
        }
        if !onAC, [20, 10].contains(where: { lastPercent > $0 && percent <= $0 }) {
            events.append(.low(percent: percent))
        }
        if onAC, lastPercent < fullLevel, percent >= fullLevel {
            events.append(.full(percent: percent))
        }
        return events
    }

    /// This Mac's battery right now, or `nil` on a desktop.
    nonisolated static func readInternalBattery() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                      .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (current * 100 / max, onAC)
        }
        return nil
    }
}
