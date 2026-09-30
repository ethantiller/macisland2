import AppKit

@MainActor
@Observable
final class TimerModel {
    enum Phase: Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    /// The shortest and longest length the dial sets: a minute, and a day (as `macisland://timer` allows).
    nonisolated static let minimumDialMinutes = 1
    nonisolated static let maximumDialMinutes = 1440

    private(set) var phase: Phase = .idle
    private(set) var duration: TimeInterval = 5 * 60

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    var isActive: Bool { phase != .idle }

    var durationMinutes: Int { Int((duration / 60).rounded()) }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .idle: duration
        case .running(let endsAt): max(endsAt.timeIntervalSince(date), 0)
        case .paused(let remaining): remaining
        }
    }

    func progress(at date: Date) -> Double {
        duration > 0 ? remaining(at: date) / duration : 0
    }

    func start(minutes: Int) {
        duration = TimeInterval(minutes * 60)
        run(for: duration)
    }

    /// Dial the length Start will use. A running or paused timer keeps the length it was given.
    func setDuration(minutes: Int) {
        guard phase == .idle else { return }
        duration = TimeInterval(min(max(minutes, Self.minimumDialMinutes), Self.maximumDialMinutes)) * 60
    }

    func toggle() {
        switch phase {
        case .idle: run(for: duration)
        case .running: pause()
        case .paused(let remaining): run(for: remaining)
        }
    }

    func addMinute() { add(minutes: 1) }

    func add(minutes: Int) {
        let seconds = TimeInterval(minutes * 60)
        duration += seconds
        switch phase {
        case .idle: break
        case .running: run(for: remaining(at: Date()) + seconds)
        case .paused(let remaining): phase = .paused(remaining: remaining + seconds)
        }
    }

    /// When the timer goes off, while it runs.
    var endDate: Date? {
        if case .running(let endsAt) = phase { endsAt } else { nil }
    }

    func reset() {
        finishTask?.cancel()
        phase = .idle
    }

    private func pause() {
        finishTask?.cancel()
        phase = .paused(remaining: remaining(at: Date()))
    }

    private func run(for seconds: TimeInterval) {
        let endsAt = Date().addingTimeInterval(seconds)
        phase = .running(endsAt: endsAt)
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(endsAt.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            self.phase = .idle
            NSSound(named: "Glass")?.play()
            self.onFinish?()
        }
    }
}
