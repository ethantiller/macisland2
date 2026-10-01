import Foundation

/// The two windows a plan limits: a session (five hours) and a week.
enum AgentLimitKind: String, Codable, CaseIterable {
    case session, week

    var title: String { self == .session ? "Session" : "Week" }
}

/// One limit window of one agent: how much of it is used, when it resets, and how old the reading is.
struct AgentLimit: Identifiable, Equatable {
    var agent: AgentKind
    var kind: AgentLimitKind
    /// Percent used, 0 to 100. Nil for an estimate from local requests, which has no percent.
    var percent: Double?
    var resetsAt: Date?
    /// When the reading was taken, only if it is old enough to say so.
    var asOf: Date?
    var isEstimate = false

    var id: String { agent.rawValue + "-" + kind.rawValue }

    /// One window, once: the agent, which window, and when it ends.
    var windowKey: String {
        "\(agent.rawValue)-\(kind.rawValue)-\(Int((resetsAt?.timeIntervalSince1970 ?? 0) / 60))"
    }

    func isOver(threshold: Double) -> Bool {
        guard !isEstimate, asOf == nil, let percent else { return false }
        return percent >= threshold
    }
}

// MARK: Claude: the desktop app's file

/// `~/Library/Application Support/Claude/plan-usage-history.json`, written by the Claude desktop app while its menu-bar item is on.
/// Undocumented. On the owner's Mac it is version 2: `samples` of `{t, org, u: {fh, sd}}`, where `fh` is the five-hour session and `sd`
/// the seven-day window, in percent. The file has no reset times, so they are worked out from how the readings move.
enum ClaudePlanUsage {
    struct Sample: Equatable {
        var time: Date
        var organization: String?
        var fiveHour: Double?
        var sevenDay: Double?
    }

    /// A reading older than this shows its age.
    static let staleAfter: TimeInterval = 30 * 60
    static let sessionLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 86_400

    /// The samples of either version of the file: an object with `samples` (version 2), or a list, or an object with `history` or
    /// `entries` (read the same way, with the usual alternative field names). Oldest first.
    static func samples(from data: Data) -> [Sample] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var list: [[String: Any]] = []
        if let array = root as? [[String: Any]] {
            list = array
        } else if let object = root as? [String: Any] {
            for key in ["samples", "history", "entries"] {
                if let array = object[key] as? [[String: Any]] {
                    list = array
                    break
                }
            }
        }
        func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        return list.compactMap { item -> Sample? in
            guard let time = AgentLogParser.date(item["t"] ?? item["timestamp"] ?? item["time"]) else { return nil }
            let usage = (item["u"] ?? item["usage"]) as? [String: Any]
            return Sample(
                time: time, organization: (item["org"] ?? item["organization"] ?? item["orgId"]) as? String,
                fiveHour: number(usage?["fh"] ?? usage?["five_hour"]), sevenDay: number(usage?["sd"] ?? usage?["seven_day"]))
        }.sorted { $0.time < $1.time }
    }

    /// The account's organization from `~/.claude.json`: only `oauthAccount.organizationUuid` is read, never the name or email.
    static func organization(fromClaudeJSON data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let account = object["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["organizationUuid"] as? String
    }

    /// The session and week windows from the readings. `firstRequest(from, to)` is the first Claude Code request after `from` and up
    /// to `to`, which narrows the start of a session to the request that really began it.
    static func limits(
        samples all: [Sample], organization: String?, now: Date, firstRequest: (Date, Date) -> Date?
    ) -> [AgentLimit] {
        let samples = all.filter { organization == nil || $0.organization == nil || $0.organization == organization }
        guard let last = samples.last else { return [] }
        let asOf: Date? = now.timeIntervalSince(last.time) > staleAfter ? last.time : nil
        var result: [AgentLimit] = []

        if let percent = last.fiveHour, now.timeIntervalSince(last.time) <= sessionLength {
            var resets: Date?
            if percent > 0 {
                var start = last.time
                var before: Date?
                var index = samples.count - 1
                while index > 0 {
                    let previous = samples[index - 1]
                    let next = samples[index]
                    // The run ends at a zero reading, a fall, or a gap longer than a session.
                    guard let value = previous.fiveHour, value > 0, value <= (next.fiveHour ?? 0),
                        next.time.timeIntervalSince(previous.time) <= sessionLength
                    else {
                        before = previous.time
                        break
                    }
                    start = previous.time
                    index -= 1
                }
                let from = before ?? start.addingTimeInterval(-15 * 60)
                if let first = firstRequest(from, start) { start = first }
                resets = start.addingTimeInterval(sessionLength)
            }
            if resets.map({ $0 > now }) ?? true {
                result.append(
                    AgentLimit(agent: .claudeCode, kind: .session, percent: percent, resetsAt: resets, asOf: asOf))
            }
        }

        if let percent = last.sevenDay {
            var drop: Date?
            var index = samples.count - 1
            while index > 0 {
                if let current = samples[index].sevenDay, let earlier = samples[index - 1].sevenDay, current < earlier {
                    drop = samples[index].time
                    break
                }
                index -= 1
            }
            var resets: Date?
            if let drop {
                let end = drop.addingTimeInterval(weekLength)
                let hour = (end.timeIntervalSince1970 / 3600).rounded(.up) * 3600
                resets = Date(timeIntervalSince1970: hour)
            }
            if let value = resets, value <= now { resets = nil }
            result.append(AgentLimit(agent: .claudeCode, kind: .week, percent: percent, resetsAt: resets, asOf: asOf))
        }
        return result
    }
}

/// The current five-hour block of local Claude Code requests, when the Claude app's file isn't there. It has no percent: only when
/// the block ends. A block starts at a request, on the hour, and lasts five hours; a request after it starts the next.
enum EstimatedBlock {
    static func current(requests: [Date], now: Date) -> (start: Date, end: Date)? {
        var block: (start: Date, end: Date)?
        for time in requests.sorted() {
            if let current = block, time < current.end { continue }
            let hour = (time.timeIntervalSince1970 / 3600).rounded(.down) * 3600
            let start = Date(timeIntervalSince1970: hour)
            block = (start, start.addingTimeInterval(ClaudePlanUsage.sessionLength))
        }
        guard let block, block.end > now else { return nil }
        return block
    }
}

// MARK: Codex

enum CodexLimits {
    /// The windows of the newest `token_count`. 12 hours or less is the session; 6 to 8 days the week; another window is left out.
    static func limits(from reading: CodexRateLimits, now: Date) -> [AgentLimit] {
        let asOf: Date? = now.timeIntervalSince(reading.observed) > ClaudePlanUsage.staleAfter ? reading.observed : nil
        var result: [AgentLimit] = []
        for window in [reading.primary, reading.secondary].compactMap({ $0 }) {
            guard let minutes = window.windowMinutes else { continue }
            let kind: AgentLimitKind
            if minutes <= 12 * 60 {
                kind = .session
            } else if (6 * 1440...8 * 1440).contains(minutes) {
                kind = .week
            } else {
                continue
            }
            // A window that has reset since the reading says nothing about now.
            if let resets = window.resetsAt, resets <= now { continue }
            guard !result.contains(where: { $0.kind == kind }) else { continue }
            result.append(
                AgentLimit(
                    agent: .codex, kind: kind, percent: window.usedPercent, resetsAt: window.resetsAt, asOf: asOf))
        }
        return result
    }
}

// MARK: Files

enum AgentLimitFiles {
    /// The Claude app's readings, or nil if its file isn't there (it is only written while the app's menu-bar item is on).
    static func claudePlanUsage(home: URL) -> [ClaudePlanUsage.Sample]? {
        let url = home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ClaudePlanUsage.samples(from: data)
    }

    static func organization(home: URL) -> String? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")) else { return nil }
        return ClaudePlanUsage.organization(fromClaudeJSON: data)
    }
}
