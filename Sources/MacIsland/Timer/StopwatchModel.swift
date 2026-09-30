import Foundation
import Observation

@MainActor
@Observable
final class StopwatchModel {
    private(set) var runningSince: Date?
    private(set) var accumulated: TimeInterval = 0
    /// Individual lap durations, oldest first.
    private(set) var laps: [TimeInterval] = []

    var isRunning: Bool { runningSince != nil }
    var isActive: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    /// Time since the last lap (or the start).
    func currentLap(at date: Date) -> TimeInterval {
        elapsed(at: date) - laps.reduce(0, +)
    }

    func toggle(at date: Date = Date()) {
        if let runningSince {
            accumulated += date.timeIntervalSince(runningSince)
            self.runningSince = nil
        } else {
            runningSince = date
        }
    }

    func lap(at date: Date = Date()) {
        guard isRunning else { return }
        laps.append(currentLap(at: date))
    }

    func reset() {
        runningSince = nil
        accumulated = 0
        laps = []
    }
}

/// "m:ss.t" for the stopwatch.
func formatStopwatch(_ seconds: TimeInterval) -> String {
    let tenths = Int((max(seconds, 0) * 10).rounded(.down))
    return formatTime(TimeInterval(tenths / 10)) + ".\(tenths % 10)"
}
