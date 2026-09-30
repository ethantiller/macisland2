import Foundation
import IOKit.pwr_mgt
import Observation

/// How long Keep Awake lasts.
enum KeepAwakeDuration: Equatable {
    case indefinitely
    case hour
    case until(Date)

    /// When it ends, counted from `now`. `nil` means it doesn't.
    func endDate(from now: Date) -> Date? {
        switch self {
        case .indefinitely: nil
        case .hour: now.addingTimeInterval(3600)
        case .until(let date): date
        }
    }

    /// Whole hours from the next hour on, for the "until" choices.
    static func upcomingHours(from now: Date, count: Int = 12, calendar: Calendar = .current) -> [Date] {
        guard let next = calendar.nextDate(
            after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime
        ) else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .hour, value: $0, to: next) }
    }
}

/// Prevents display sleep while on, like `caffeinate -d`. macOS drops the assertion if the app quits.
@MainActor
@Observable
final class KeepAwake {
    private(set) var isOn = false
    private(set) var duration: KeepAwakeDuration = .indefinitely

    @ObservationIgnored private var assertionID = IOPMAssertionID(0)
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    /// The tool button: on indefinitely, or off.
    func toggle() {
        if isOn { stop() } else { start(.indefinitely) }
    }

    /// Turns Keep Awake on, or changes how long it lasts while it's on.
    func start(_ duration: KeepAwakeDuration, now: Date = Date()) {
        if !isOn {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "MacIsland Keep Awake" as CFString,
                &assertionID
            )
            guard result == kIOReturnSuccess else { return }
            isOn = true
        }
        self.duration = duration
        expiryTask?.cancel()
        expiryTask = nil
        guard let end = duration.endDate(from: now) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        guard isOn else { return }
        IOPMAssertionRelease(assertionID)
        isOn = false
        duration = .indefinitely
    }
}
