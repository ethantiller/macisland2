import AppKit
import Observation

enum PomodoroPhase: Equatable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long Break"
        }
    }
}

/// How long each phase lasts, in minutes, and how many focus sessions come before the long break. The person's choice
/// (Settings, Clock); the defaults are the classic 25, 5, 15, and 4.
struct PomodoroPlan: Equatable {
    static let focusRange = 1...90
    static let shortBreakRange = 1...30
    static let longBreakRange = 5...60
    static let sessionsRange = 2...8

    static let `default` = PomodoroPlan(focus: 25, shortBreak: 5, longBreak: 15, sessions: 4)

    var focus: Int
    var shortBreak: Int
    var longBreak: Int
    var sessions: Int

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: TimeInterval(focus * 60)
        case .shortBreak: TimeInterval(shortBreak * 60)
        case .longBreak: TimeInterval(longBreak * 60)
        }
    }
}

/// Completed focus sessions per day, for the streak and the 7-day chart.
struct PomodoroHistory: Codable, Equatable {
    private(set) var days: [String: Int] = [:]

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    mutating func record(on date: Date, calendar: Calendar = .current) {
        days[Self.key(for: date, calendar: calendar), default: 0] += 1
    }

    func count(on date: Date, calendar: Calendar = .current) -> Int {
        days[Self.key(for: date, calendar: calendar)] ?? 0
    }

    /// Days in a row with at least one session. Today not having one yet doesn't break yesterday's streak.
    func streak(asOf date: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if count(on: day, calendar: calendar) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while count(on: day, calendar: calendar) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The last seven days, oldest first, ending today.
    func lastSevenDays(asOf date: Date, calendar: Calendar = .current) -> [(date: Date, count: Int)] {
        let today = calendar.startOfDay(for: date)
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, count(on: $0, calendar: calendar)) }
        }
    }
}

/// Focus and break sessions that chain on their own: the plan's number of focus sessions with short breaks, then a
/// long break, and it stops there. A phase that is running keeps the length it started with; a change to the plan
/// applies from the next phase, and to the ring at once while nothing is running.
@MainActor
@Observable
final class PomodoroModel {
    enum RunState: Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    private(set) var phase: PomodoroPhase = .focus
    private(set) var runState: RunState = .idle
    /// Focus sessions finished in the current cycle.
    private(set) var focusInCycle = 0
    private(set) var history: PomodoroHistory

    /// A phase ended and the next one has started (or the cycle is over and it is idle).
    @ObservationIgnored var onPhaseEnd: ((_ finished: PomodoroPhase, _ next: PomodoroPhase) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let planSource: @MainActor () -> PomodoroPlan
    /// The length of the phase in progress, frozen when it starts so a change to the plan doesn't stretch it.
    @ObservationIgnored private var startedLength: TimeInterval?
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    private static let historyKey = "pomodoro.history"

    /// `plan` is read whenever it is needed, so the model follows the person's settings without being told. It is a value
    /// handed in, not `UserDefaults.standard`, so tests and the Settings preview stay apart from the real app.
    init(
        defaults: UserDefaults = .standard, calendar: Calendar = .current,
        plan: @escaping @MainActor () -> PomodoroPlan = { .default }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        planSource = plan
        history =
            defaults.data(forKey: Self.historyKey)
            .flatMap { try? JSONDecoder().decode(PomodoroHistory.self, from: $0) } ?? PomodoroHistory()
    }

    var plan: PomodoroPlan { planSource() }

    var isActive: Bool { runState != .idle }

    /// How long the current phase is: the length it started with while it runs or is paused, the plan's while idle.
    var phaseLength: TimeInterval {
        isActive ? startedLength ?? plan.duration(of: phase) : plan.duration(of: phase)
    }

    var isRunning: Bool {
        if case .running = runState { return true }
        return false
    }

    func remaining(at date: Date) -> TimeInterval {
        switch runState {
        case .idle: plan.duration(of: phase)
        case .running(let endsAt): max(endsAt.timeIntervalSince(date), 0)
        case .paused(let remaining): remaining
        }
    }

    func progress(at date: Date) -> Double {
        phaseLength > 0 ? remaining(at: date) / phaseLength : 0
    }

    var streak: Int { history.streak(asOf: Date(), calendar: calendar) }

    func toggle() {
        switch runState {
        case .idle: run(for: plan.duration(of: phase), startsPhase: true)
        case .running: pause()
        case .paused(let remaining): run(for: remaining, startsPhase: false)
        }
    }

    /// Moves to the next phase without giving credit for the one skipped.
    func skip() {
        advance(completed: false)
    }

    func reset() {
        finishTask?.cancel()
        runState = .idle
        startedLength = nil
        phase = .focus
        focusInCycle = 0
    }

    /// What follows `phase` once `focusFinished` of `sessions` focus sessions are done. `nil` ends the cycle.
    static func next(after phase: PomodoroPhase, focusFinished: Int, sessions: Int) -> PomodoroPhase? {
        switch phase {
        case .focus: focusFinished >= sessions ? .longBreak : .shortBreak
        case .shortBreak: .focus
        case .longBreak: nil
        }
    }

    /// Ends the current phase now: credit a finished focus session, then start the next phase.
    func advance(completed: Bool, at date: Date = Date()) {
        finishTask?.cancel()
        let finished = phase
        if completed, finished == .focus {
            focusInCycle += 1
            history.record(on: date, calendar: calendar)
            defaults.set(try? JSONEncoder().encode(history), forKey: Self.historyKey)
        }
        // A cycle under way is judged against the plan as it is now: lowering the count below the sessions already done
        // makes the next focus session the last.
        if let next = Self.next(after: finished, focusFinished: focusInCycle, sessions: plan.sessions) {
            phase = next
            run(for: plan.duration(of: next), from: date, startsPhase: true)
        } else {
            phase = .focus
            focusInCycle = 0
            startedLength = nil
            runState = .idle
        }
        if completed { onPhaseEnd?(finished, phase) }
    }

    private func pause() {
        finishTask?.cancel()
        runState = .paused(remaining: remaining(at: Date()))
    }

    /// `startsPhase` is false when a paused phase resumes, which keeps the length it started with.
    private func run(for seconds: TimeInterval, from now: Date = Date(), startsPhase: Bool) {
        if startsPhase { startedLength = seconds }
        let endsAt = now.addingTimeInterval(seconds)
        runState = .running(endsAt: endsAt)
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(endsAt.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            NSSound(named: "Glass")?.play()
            self.advance(completed: true)
        }
    }
}
