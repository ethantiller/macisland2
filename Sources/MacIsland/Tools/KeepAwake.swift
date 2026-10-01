import AppKit
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
        guard
            let next = calendar.nextDate(
                after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime
            )
        else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .hour, value: $0, to: next) }
    }
}

/// The two kinds of sleep Keep Awake holds off.
enum PowerAssertionKind: Equatable {
    /// The display (and with it idle sleep): `caffeinate -d`.
    case displaySleep
    /// The whole system going to sleep: `kIOPMAssertionTypePreventSystemSleep`. macOS honors it only in some situations (on power, for
    /// one), so it is held in addition and never relied on.
    case systemSleep
}

/// IOKit's power assertions, behind a protocol so tests don't touch the real ones.
@MainActor
protocol PowerAssertions: AnyObject {
    /// Makes an assertion, or nil when the system refuses.
    func create(_ kind: PowerAssertionKind, name: String) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
    /// Whether the system still has it.
    func exists(_ id: IOPMAssertionID) -> Bool
}

@MainActor
final class LivePowerAssertions: PowerAssertions {
    func create(_ kind: PowerAssertionKind, name: String) -> IOPMAssertionID? {
        let type =
            switch kind {
            case .displaySleep: kIOPMAssertionTypePreventUserIdleDisplaySleep
            case .systemSleep: kIOPMAssertionTypePreventSystemSleep
            }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }

    func release(_ id: IOPMAssertionID) { IOPMAssertionRelease(id) }

    func exists(_ id: IOPMAssertionID) -> Bool { IOPMAssertionCopyProperties(id) != nil }
}

/// Keeps the display awake while on, like `caffeinate -d`, and also holds a system-sleep assertion. **It does not promise the lid**: closing the
/// lid of a MacBook with no power and no external display sleeps it whatever an assertion says, so the tool says so in words. macOS drops the
/// assertions if the app quits, and after the Mac wakes they are checked, so "on" is never shown when nothing is held.
/// See docs/plans/keep-awake-lid.md.
@MainActor
@Observable
final class KeepAwake {
    private(set) var isOn = false
    private(set) var duration: KeepAwakeDuration = .indefinitely
    /// When it ends, if it does.
    private(set) var endsAt: Date?

    /// What the tool says it does, and doesn't.
    static let limits = "Keeps the display awake. Closing the lid can still sleep this Mac unless it is on power with an external display."

    @ObservationIgnored private let assertions: PowerAssertions
    @ObservationIgnored private var held: [IOPMAssertionID] = []
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: Any?

    init(assertions: PowerAssertions? = nil, observesWake: Bool = true) {
        self.assertions = assertions ?? LivePowerAssertions()
        guard observesWake else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    /// The tool button: on indefinitely, or off.
    func toggle() {
        if isOn { stop() } else { start(.indefinitely) }
    }

    /// Turns Keep Awake on, or changes how long it lasts while it's on.
    func start(_ duration: KeepAwakeDuration, now: Date = Date()) {
        if !isOn {
            // The display assertion is the one the tool stands on; the system one is a bonus that may be refused.
            guard let display = assertions.create(.displaySleep, name: "MacIsland Keep Awake") else { return }
            held = [display]
            if let system = assertions.create(.systemSleep, name: "MacIsland Keep Awake") { held.append(system) }
            isOn = true
        }
        self.duration = duration
        expiryTask?.cancel()
        expiryTask = nil
        endsAt = duration.endDate(from: now)
        guard let end = endsAt else { return }
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
        for id in held { assertions.release(id) }
        held = []
        isOn = false
        duration = .indefinitely
        endsAt = nil
    }

    /// After the Mac wakes: if the system no longer holds the display assertion, it is off, and the tool says so.
    func reconcile() {
        guard isOn else { return }
        guard let display = held.first, assertions.exists(display) else {
            for id in held where assertions.exists(id) { assertions.release(id) }
            held = []
            expiryTask?.cancel()
            expiryTask = nil
            isOn = false
            duration = .indefinitely
            endsAt = nil
            return
        }
    }
}

/// Keep Awake's time left, as the closed island words it.
enum KeepAwakeTime {
    /// "45m" up to an hour, "1h35" past it, rounded up to the minute: a fresh hour reads "60m".
    static func text(remaining: TimeInterval) -> String {
        let minutes = max(Int((remaining / 60).rounded(.up)), 0)
        guard minutes > 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h" + String(format: "%02d", minutes % 60)
    }
}
