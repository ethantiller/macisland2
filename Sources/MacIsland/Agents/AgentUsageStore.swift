import Foundation

// What the agents used. Claude Code writes the token counts of every request into its log; Codex writes a `token_count` event after
// each. Both are undocumented. A line that doesn't decode is skipped.
//
// Claude Code: an "assistant" line with message.usage (input_tokens, output_tokens, cache_read_input_tokens,
// cache_creation_input_tokens, and cache_creation.ephemeral_5m_input_tokens / ephemeral_1h_input_tokens), message.model, message.id,
// and requestId. A response that streams is written more than once: it counts once, by message.id plus requestId.
// Codex: event_msg / token_count with info.last_token_usage (input_tokens including cached_input_tokens, output_tokens) and
// rate_limits; the model comes from the turn_context before it, the folder from session_meta. **Verify** on a Mac with Codex.

/// One request's tokens, from a log line.
struct AgentUsageRecord: Equatable {
    var agent: AgentKind
    /// What makes two lines the same response, or nil if the line has no such identity.
    var identity: String?
    var date: Date
    var model: String
    var cwd: String?
    var tokens: AgentTokens
}

/// Codex's rate-limit windows, as the newest `token_count` event reported them.
struct CodexRateLimits: Codable, Equatable {
    struct Window: Codable, Equatable {
        var usedPercent: Double
        var windowMinutes: Int?
        var resetsAt: Date?
    }

    var observed: Date
    var primary: Window?
    var secondary: Window?
}

/// What one log line says about usage.
enum AgentUsageLine: Equatable {
    case request(AgentUsageRecord)
    /// Codex: the folder, model, or session a later `token_count` belongs to.
    case context(cwd: String?, model: String?, session: String?)
    case rateLimits(CodexRateLimits, request: AgentUsageRecord?)
}

enum AgentUsageParser {
    /// Cheap checks before a line is decoded: most of a log is not usage.
    static func mightBeUsage(_ line: String, agent: AgentKind) -> Bool {
        switch agent {
        case .claudeCode: line.contains("\"output_tokens\"")
        case .codex: line.contains("token_count") || line.contains("turn_context") || line.contains("session_meta")
        }
    }

    static func parse(_ line: String, agent: AgentKind, context: (model: String?, cwd: String?, session: String?) = (nil, nil, nil))
        -> AgentUsageLine?
    {
        guard mightBeUsage(line, agent: agent), let data = line.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        switch agent {
        case .claudeCode: return claude(object)
        case .codex: return codex(object, context: context)
        }
    }

    private static func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }

    private static func claude(_ object: [String: Any]) -> AgentUsageLine? {
        guard object["type"] as? String == "assistant", object["isApiErrorMessage"] as? Bool != true,
            let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
            let model = message["model"] as? String, model != "<synthetic>", let date = AgentLogParser.date(object["timestamp"])
        else { return nil }
        var tokens = AgentTokens(
            input: int(usage["input_tokens"]), output: int(usage["output_tokens"]),
            cacheRead: int(usage["cache_read_input_tokens"]))
        if let split = usage["cache_creation"] as? [String: Any] {
            tokens.cacheWrite = int(split["ephemeral_5m_input_tokens"])
            tokens.cacheWrite1h = int(split["ephemeral_1h_input_tokens"])
        } else {
            tokens.cacheWrite = int(usage["cache_creation_input_tokens"])
        }
        guard tokens.total > 0 else { return nil }
        var identity: String?
        if let id = message["id"] as? String, let request = object["requestId"] as? String { identity = id + ":" + request }
        return .request(
            AgentUsageRecord(
                agent: .claudeCode, identity: identity, date: date, model: model, cwd: object["cwd"] as? String, tokens: tokens))
    }

    private static func codex(_ object: [String: Any], context: (model: String?, cwd: String?, session: String?)) -> AgentUsageLine? {
        guard let type = object["type"] as? String else { return nil }
        let payload = object["payload"] as? [String: Any]
        switch type {
        case "session_meta":
            return .context(cwd: payload?["cwd"] as? String, model: nil, session: payload?["id"] as? String)
        case "turn_context":
            return .context(cwd: payload?["cwd"] as? String, model: payload?["model"] as? String, session: nil)
        case "event_msg":
            guard payload?["type"] as? String == "token_count" else { return nil }
            let date = AgentLogParser.date(object["timestamp"]) ?? Date()
            var request: AgentUsageRecord?
            if let info = payload?["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any],
                let model = context.model
            {
                let input = int(last["input_tokens"])
                let cached = min(int(last["cached_input_tokens"]), input)
                let tokens = AgentTokens(input: input - cached, output: int(last["output_tokens"]), cacheRead: cached)
                if tokens.total > 0 {
                    let total = int((info["total_token_usage"] as? [String: Any])?["total_tokens"])
                    let identity = (payload?["response_id"] as? String).map { "codex:" + $0 }
                        ?? "codex:\(context.session ?? "-"):\(total)"
                    request = AgentUsageRecord(
                        agent: .codex, identity: identity, date: date, model: model, cwd: context.cwd, tokens: tokens)
                }
            }
            if let limits = payload?["rate_limits"] as? [String: Any] {
                let reading = CodexRateLimits(
                    observed: date, primary: window(limits["primary"], observed: date),
                    secondary: window(limits["secondary"], observed: date))
                return .rateLimits(reading, request: request)
            }
            return request.map { .request($0) }
        default:
            return nil
        }
    }

    private static func window(_ value: Any?, observed: Date) -> CodexRateLimits.Window? {
        guard let object = value as? [String: Any], let used = (object["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        var resets: Date?
        if let at = (object["resets_at"] as? NSNumber)?.doubleValue {
            resets = Date(timeIntervalSince1970: at > 1e11 ? at / 1000 : at)
        } else if let after = (object["resets_in_seconds"] as? NSNumber)?.doubleValue {
            resets = observed.addingTimeInterval(after)
        }
        return CodexRateLimits.Window(
            usedPercent: used, windowMinutes: (object["window_minutes"] as? NSNumber)?.intValue, resetsAt: resets)
    }
}

// MARK: Aggregates

/// A calendar day as a number that sorts: 20261001.
enum UsageDay {
    static func key(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    static func date(_ key: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100))
    }
}

/// Everything one agent, model, and project used on one day.
struct UsageBucket: Codable, Equatable {
    var day: Int
    var agent: AgentKind
    var model: String
    var project: String
    var tokens: AgentTokens
    var requests: Int

    var key: String { "\(day)|\(agent.rawValue)|\(model)|\(project)" }
}

/// What was read of one log file.
struct AgentFileState: Codable, Equatable {
    var offset: UInt64 = 0
    var inode: UInt64 = 0
    var cwd: String?
    var model: String?
    var session: String?
}

/// The store's whole memory, which is also what the cache file holds.
struct AgentUsageData: Codable, Equatable {
    static let version = 1
    var version = AgentUsageData.version
    /// How far each log has been read.
    var files: [String: AgentFileState] = [:]
    var buckets: [String: UsageBucket] = [:]
    /// Responses counted already (a hash of their identity) and the day they were on, so a response copied into another log, or a log
    /// read again, counts once.
    var seen: [UInt64: Int] = [:]
    /// When Claude Code requests were made in the last eight days, for the start of the current session. Seconds since 1970, oldest first.
    var requestTimes: [Double] = []
    var codex: CodexRateLimits?
    /// Limit windows already announced: the window and when it ends.
    var fired: [String: Double] = [:]

    static let requestWindow: TimeInterval = 8 * 86_400
    static let keepsDays = 91

    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value = (value ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return value & 0x1F_FFFF_FFFF_FFFF
    }

    /// Adds a request unless its response was counted. Returns whether it counted.
    @discardableResult
    mutating func add(_ record: AgentUsageRecord, cwd: String?, now: Date, calendar: Calendar) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(Self.keepsDays) * 86_400)
        guard record.date >= cutoff else { return false }
        let day = UsageDay.key(record.date, calendar: calendar)
        if let identity = record.identity {
            let hash = Self.hash(identity)
            if seen[hash] != nil { return false }
            seen[hash] = day
        }
        let project = AgentLogParser.project(fromCwd: record.cwd ?? cwd)
        let key = "\(day)|\(record.agent.rawValue)|\(record.model)|\(project)"
        var bucket =
            buckets[key]
            ?? UsageBucket(day: day, agent: record.agent, model: record.model, project: project, tokens: AgentTokens(), requests: 0)
        bucket.tokens += record.tokens
        bucket.requests += 1
        buckets[key] = bucket
        if record.agent == .claudeCode, now.timeIntervalSince(record.date) <= Self.requestWindow {
            requestTimes.append(record.date.timeIntervalSince1970)
        }
        return true
    }

    /// Drops what is older than 91 days.
    mutating func prune(now: Date, calendar: Calendar) {
        let cutoffDay = UsageDay.key(now.addingTimeInterval(-Double(Self.keepsDays) * 86_400), calendar: calendar)
        buckets = buckets.filter { $0.value.day >= cutoffDay }
        seen = seen.filter { $0.value >= cutoffDay }
        let earliest = now.timeIntervalSince1970 - Self.requestWindow
        requestTimes = requestTimes.filter { $0 >= earliest }.sorted()
        fired = fired.filter { $0.value > now.timeIntervalSince1970 }
    }
}

/// What the views show, copied out of the store.
struct AgentUsageSnapshot {
    var buckets: [UsageBucket] = []
    var limits: [AgentLimit] = []
    /// Limits that crossed the threshold on this refresh, for the notice.
    var newlyOver: [AgentLimit] = []
    var generated = Date()
    /// Whether the Claude app's file was found: without it the module says its limits are an estimate.
    var hasClaudePlanFile = false

    var hasUsage: Bool { !buckets.isEmpty }
}

/// What a refresh needs to know that the store doesn't.
struct AgentUsageRequest {
    var readsClaude = true
    var readsCodex = true
    /// The percent at which a window is announced.
    var threshold = 80
}

// MARK: Store

/// The history of what the agents used, read once and then kept up to date. An actor, so the first read of hundreds of megabytes is
/// off the main actor; the caller runs it at utility priority.
///
/// A file is read from where it was left (its offset), unless its inode changed or it got shorter, and then it is read again from the
/// start (a response is never counted twice, so that is safe). What is read is kept in a cache file so the next launch reads only what
/// was added.
actor AgentUsageStore {
    private let home: URL
    private let cacheURL: URL
    private let calendar: Calendar
    private var data = AgentUsageData()
    private var loaded = false
    private var dirty = false
    private var known: [(path: String, agent: AgentKind)] = []
    private var lastScan: Date?
    /// The most a chunk of a log is read at once.
    private let chunk = 4 << 20

    static func defaultCacheURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.ethantiller.MacIsland/Agents/usage.json")
    }

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, cacheURL: URL = AgentUsageStore.defaultCacheURL(),
        calendar: Calendar = .current
    ) {
        self.home = home
        self.cacheURL = cacheURL
        self.calendar = calendar
    }

    // MARK: Refresh

    func refresh(_ request: AgentUsageRequest, now: Date = Date()) -> AgentUsageSnapshot {
        load()
        scan(now: now)
        for file in known where isWanted(file.agent, request) { read(file.path, agent: file.agent, now: now) }
        data.prune(now: now, calendar: calendar)
        return snapshot(request, now: now)
    }

    /// Forgets everything, including the cache file, as when Agents is switched off.
    func clear() {
        data = AgentUsageData()
        known = []
        lastScan = nil
        loaded = true
        dirty = false
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func isWanted(_ agent: AgentKind, _ request: AgentUsageRequest) -> Bool {
        agent == .claudeCode ? request.readsClaude : request.readsCodex
    }

    // MARK: Files

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let bytes = try? Data(contentsOf: cacheURL),
            let stored = try? JSONDecoder().decode(AgentUsageData.self, from: bytes), stored.version == AgentUsageData.version
        else { return }
        data = stored
    }

    private func save() {
        guard dirty else { return }
        dirty = false
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: cacheURL, options: .atomic)
        } catch {
            // A cache that can't be written costs a re-read next launch, nothing more.
        }
    }

    /// The log files changed in the window. The folder walk is repeated at most once a minute; between, the known files are looked at.
    private func scan(now: Date) {
        if let lastScan, now.timeIntervalSince(lastScan) < 60 { return }
        lastScan = now
        let earliest = now.addingTimeInterval(-Double(AgentUsageData.keepsDays) * 86_400)
        var found: [(path: String, agent: AgentKind)] = []
        for root in AgentLogLocations.roots(home: home) {
            guard
                let walker = FileManager.default.enumerator(
                    at: root.url, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified >= earliest { found.append((url.path, root.agent)) }
            }
        }
        known = found
        let paths = Set(found.map(\.path))
        let before = data.files.count
        data.files = data.files.filter { paths.contains($0.key) }
        if data.files.count != before { dirty = true }
    }

    private func read(_ path: String, agent: AgentKind, now: Date) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        var state = data.files[path] ?? AgentFileState()
        if state.inode != 0 && state.inode != inode || size < state.offset { state = AgentFileState() }
        state.inode = inode
        guard size > state.offset else {
            if data.files[path] != state { data.files[path] = state; dirty = true }
            return
        }
        var limit = chunk
        while true {
            guard let tail = AgentLogTail.read(URL(fileURLWithPath: path), from: state.offset, limit: limit) else { break }
            if tail.lines.isEmpty {
                // A line longer than the chunk: take more, up to a sane size. Otherwise there is nothing more to read.
                if tail.offset == state.offset && size > state.offset + UInt64(limit) && limit < (64 << 20) {
                    limit *= 4
                    continue
                }
                break
            }
            limit = chunk
            ingest(tail.lines, agent: agent, state: &state, now: now)
            state.offset = tail.offset
            if state.offset >= size { break }
        }
        data.files[path] = state
        dirty = true
    }

    private func ingest(_ lines: [String], agent: AgentKind, state: inout AgentFileState, now: Date) {
        for line in lines where AgentUsageParser.mightBeUsage(line, agent: agent) {
            let context = (model: state.model, cwd: state.cwd, session: state.session)
            guard let parsed = AgentUsageParser.parse(line, agent: agent, context: context) else { continue }
            switch parsed {
            case .request(let record):
                data.add(record, cwd: state.cwd, now: now, calendar: calendar)
            case .context(let cwd, let model, let session):
                state.cwd = cwd ?? state.cwd
                state.model = model ?? state.model
                state.session = session ?? state.session
            case .rateLimits(let limits, let request):
                if let request { data.add(request, cwd: state.cwd, now: now, calendar: calendar) }
                if limits.observed >= (data.codex?.observed ?? .distantPast) { data.codex = limits }
            }
        }
    }

    // MARK: Snapshot

    private func snapshot(_ request: AgentUsageRequest, now: Date) -> AgentUsageSnapshot {
        var snapshot = AgentUsageSnapshot()
        snapshot.generated = now
        snapshot.buckets = data.buckets.values.filter { request.readsClaude || $0.agent != .claudeCode }
            .filter { request.readsCodex || $0.agent != .codex }
        let requests = data.requestTimes.map { Date(timeIntervalSince1970: $0) }
        var limits: [AgentLimit] = []
        if request.readsClaude {
            let file = AgentLimitFiles.claudePlanUsage(home: home)
            snapshot.hasClaudePlanFile = file != nil
            if let file, !file.isEmpty {
                limits += ClaudePlanUsage.limits(
                    samples: file, organization: AgentLimitFiles.organization(home: home), now: now,
                    firstRequest: { from, to in requests.first { $0 > from && $0 <= to } })
            }
            if !limits.contains(where: { $0.agent == .claudeCode && $0.kind == .session }),
                let block = EstimatedBlock.current(requests: requests, now: now)
            {
                limits.append(
                    AgentLimit(
                        agent: .claudeCode, kind: .session, percent: nil, resetsAt: block.end, asOf: nil, isEstimate: true))
            }
        }
        if request.readsCodex, let codex = data.codex { limits += CodexLimits.limits(from: codex, now: now) }
        snapshot.limits = limits
        // Announce once per window.
        for limit in limits where limit.isOver(threshold: Double(request.threshold)) {
            guard let ends = limit.resetsAt else { continue }
            let key = limit.windowKey
            if data.fired[key] == nil {
                data.fired[key] = ends.timeIntervalSince1970
                dirty = true
                snapshot.newlyOver.append(limit)
            }
        }
        save()
        return snapshot
    }
}
