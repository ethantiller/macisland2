import Foundation
import Observation

/// A task an agent is working on now.
struct AgentTask: Identifiable, Equatable {
    /// The session, so a session has one task at a time.
    let id: String
    var agent: AgentKind
    var project: String
    var model: String?
    var startedAt: Date
    var lastActivity: Date
}

/// What the agents are doing, from the lines their logs gain. Pure state, so it is tested without a file: `ingest` takes parsed lines,
/// and the watcher behind `AgentLogWatching` is the only thing that touches the disk.
///
/// A turn is open from the prompt to the end of the answer. It shows for as long as the log keeps changing; with no line for ten
/// minutes it stops showing (a crash can leave a turn open), and a later line shows it again. Nothing polls: while a turn is open, one
/// task sleeps until the earliest of those deadlines.
@MainActor
@Observable
final class AgentActivity {
    /// With no line for this long, a turn is no longer shown.
    static let idleLimit: TimeInterval = 600
    /// A turn that ended longer ago than this is never announced.
    static let announceWindow: TimeInterval = 300

    /// What the agents used, their plan limits, and the activity map: the history behind the Usage and Activity modes.
    let usage: AgentUsageModel

    /// What is working now, longest-running first.
    var liveTasks: [AgentTask] {
        _ = tick
        let now = clock()
        return open.values.filter { now.timeIntervalSince($0.lastActivity) < Self.idleLimit }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// A turn ended well: how long it took, and when it ended. Set by the app, which flashes the notice.
    @ObservationIgnored var onFinish: ((AgentTask, TimeInterval) -> Void)?
    /// The shortest turn worth a notice, read when a turn ends so a change in Settings applies at once.
    @ObservationIgnored var minimumDuration: () -> TimeInterval = { 60 }

    @ObservationIgnored private var open: [String: AgentTask] = [:]
    /// The process behind a Claude Code session, to tell a turn that was cut off by quitting from one still working.
    @ObservationIgnored private var processes: [String: Int32] = [:]
    /// What a session's lines said about its model and folder, for a turn that starts after them.
    @ObservationIgnored private var meta: [String: (model: String?, cwd: String?)] = [:]
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private let clock: () -> Date
    /// Changes when a deadline passes, so what shows is looked at again.
    private var tick = 0

    init(clock: @escaping () -> Date = Date.init, usage: AgentUsageModel = AgentUsageModel()) {
        self.clock = clock
        self.usage = usage
    }

    // MARK: Lines in

    /// One parsed line of a session's log. `announces` is false for lines read from before the app was watching.
    func ingest(
        _ event: AgentLogEvent, agent: AgentKind, session: String, cwd: String? = nil, announces: Bool = true
    ) {
        let now = clock()
        let seen = event.date ?? now
        let known = meta[session]
        switch event.kind {
        case .turnStarted:
            var task =
                open[session]
                ?? AgentTask(
                    id: session, agent: agent,
                    project: AgentLogParser.project(fromCwd: event.cwd ?? cwd ?? known?.cwd), model: known?.model,
                    startedAt: seen, lastActivity: seen)
            if open[session] != nil { task.lastActivity = max(seen, task.lastActivity) }
            task.model = event.model ?? task.model
            open[session] = task
        case .activity:
            if event.model != nil || event.cwd != nil {
                meta[session] = (event.model ?? known?.model, event.cwd ?? known?.cwd)
            }
            guard var task = open[session] else { return }
            task.lastActivity = max(seen, task.lastActivity)
            if let model = event.model { task.model = model }
            if let folder = event.cwd ?? cwd { task.project = AgentLogParser.project(fromCwd: folder) }
            open[session] = task
        case .turnEnded(let outcome):
            meta[session] = nil
            guard let task = open.removeValue(forKey: session) else { break }
            let duration = seen.timeIntervalSince(task.startedAt)
            if announces, outcome == .finished, duration >= minimumDuration(),
                now.timeIntervalSince(seen) <= Self.announceWindow
            {
                onFinish?(task, duration)
            }
        }
        changed()
    }

    // MARK: Sessions that went away

    /// The Claude Code processes: session to pid.
    func setProcesses(_ list: [String: Int32]) {
        processes = list
    }

    /// Ends, quietly, the turns of sessions whose process is gone. A turn whose process isn't known stays until its deadline.
    func endTurnsOfDeadSessions(isAlive: (Int32) -> Bool) {
        var changedAny = false
        for (session, pid) in processes where open[session] != nil && !isAlive(pid) {
            open[session] = nil
            changedAny = true
        }
        if changedAny { changed() }
    }

    // MARK: Stopping

    /// Forgets everything, as when Agents is switched off.
    func reset() {
        open = [:]
        meta = [:]
        processes = [:]
        deadline?.cancel()
        deadline = nil
        tick += 1
        usage.stop()
    }

    // MARK: The deadline

    private func changed() {
        tick += 1
        scheduleDeadline()
    }

    /// One sleep, until the earliest turn would stop showing. No repeating timer.
    private func scheduleDeadline() {
        deadline?.cancel()
        deadline = nil
        // Only a deadline still to come needs a wake: one that has passed is already not shown, and a later line looks again.
        let now = clock()
        let upcoming = open.values.map { $0.lastActivity.addingTimeInterval(Self.idleLimit) }.filter { $0 > now }
        guard let earliest = upcoming.min() else { return }
        let wait = earliest.timeIntervalSince(now) + 0.5
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.changed()
        }
    }
}
