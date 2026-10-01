import Foundation
import Testing

@testable import MacIsland

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func json(_ object: [String: Any]) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
}

/// A Claude Code assistant line, with the shape of the real ones and made-up numbers.
private func claudeLine(
    at date: Date, id: String? = "msg_1", request: String? = "req_1", model: String = "claude-opus-4-5-20251101",
    input: Int = 10, output: Int = 20, cacheRead: Int = 0, cacheWrite: Int = 0, cwd: String = "/Users/me/code/island"
) -> String {
    var message: [String: Any] = [
        "model": model, "stop_reason": "end_turn",
        "usage": [
            "input_tokens": input, "output_tokens": output, "cache_read_input_tokens": cacheRead,
            "cache_creation_input_tokens": cacheWrite,
        ],
    ]
    if let id { message["id"] = id }
    var object: [String: Any] = ["type": "assistant", "timestamp": iso(date), "cwd": cwd, "message": message]
    if let request { object["requestId"] = request }
    return json(object)
}

private func price(_ model: String) -> AgentPricing {
    AgentPricing(
        updated: "2026-10-01",
        models: [
            "opus-4-5": AgentPrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25, cacheWrite1h: 10),
            "sonnet-4": AgentPrice(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75, cacheWrite1h: 6),
        ])
}

struct AgentPricingTests {
    @Test func pricesApplyPerCategory() {
        let pricing = price("")
        let model = "claude-opus-4-5-20251101"
        #expect(pricing.cost(of: AgentTokens(input: 1_000_000), model: model) == 5)
        #expect(pricing.cost(of: AgentTokens(output: 1_000_000), model: model) == 25)
        #expect(pricing.cost(of: AgentTokens(cacheRead: 1_000_000), model: model) == 0.5)
        #expect(pricing.cost(of: AgentTokens(cacheWrite: 1_000_000), model: model) == 6.25)
        #expect(pricing.cost(of: AgentTokens(cacheWrite1h: 1_000_000), model: model) == 10)
        #expect(pricing.cost(of: AgentTokens(input: 500_000, output: 500_000), model: model) == 15)
    }

    @Test func theLongestPrefixWinsAtADash() {
        let pricing = AgentPricing(
            models: [
                "opus-4": AgentPrice(input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75),
                "opus-4-5": AgentPrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),
            ])
        #expect(pricing.price(for: "claude-opus-4-5-20251101")?.input == 5)
        #expect(pricing.price(for: "claude-opus-4-1-20250805")?.input == 15)
        #expect(pricing.price(for: "claude-opus-45") == nil, "a prefix must end at a dash")
        #expect(pricing.price(for: "gpt-5") == nil)
    }

    @Test func anUnknownModelMakesTheTotalAtLeast() {
        let day = UsageDay.key(Date(), calendar: utc)
        let known = UsageBucket(
            day: day, agent: .claudeCode, model: "claude-opus-4-5-20251101", project: "p",
            tokens: AgentTokens(input: 1_000_000), requests: 1)
        let unknown = UsageBucket(
            day: day, agent: .codex, model: "gpt-9", project: "p", tokens: AgentTokens(input: 1_000_000), requests: 1)
        let summary = AgentUsageSummary.make(
            buckets: [known, unknown], range: .today, now: Date(), pricing: price(""), calendar: utc)
        #expect(summary.value == 5 && summary.isLowerBound)
        #expect(summary.tokens == 2_000_000)
        let alone = AgentUsageSummary.make(buckets: [known], range: .today, now: Date(), pricing: price(""), calendar: utc)
        #expect(!alone.isLowerBound)
    }

    @Test func cacheSavingIsReadTimesTheDifference() {
        let pricing = price("")
        #expect(pricing.cacheSaving(of: AgentTokens(cacheRead: 2_000_000), model: "claude-opus-4-5-20251101") == 9)
        #expect(pricing.cacheSaving(of: AgentTokens(cacheRead: 1), model: "unknown") == nil)
    }

    @Test func theBundledTableDecodes() throws {
        let text = """
            {"updated": "2026-10-01", "models": {"opus-4-5": {"input": 5, "output": 25, "cacheRead": 0.5, "cacheWrite": 6.25}}}
            """
        let pricing = try #require(AgentPricing(data: Data(text.utf8)))
        #expect(pricing.price(for: "claude-opus-4-5-20251101")?.cacheWrite1h == nil)
        #expect(AgentPricing(data: Data("nope".utf8)) == nil)
    }
}

struct AgentUsageDataTests {
    private let now = Date()

    private func record(
        at date: Date, identity: String? = "a", model: String = "m", cwd: String? = "/x/proj", input: Int = 1
    ) -> AgentUsageRecord {
        AgentUsageRecord(
            agent: .claudeCode, identity: identity, date: date, model: model, cwd: cwd, tokens: AgentTokens(input: input))
    }

    @Test func duplicatesAreCountedOnce() {
        var data = AgentUsageData()
        #expect(data.add(record(at: now), cwd: nil, now: now, calendar: utc))
        #expect(!data.add(record(at: now), cwd: nil, now: now, calendar: utc))
        #expect(data.add(record(at: now, identity: "b"), cwd: nil, now: now, calendar: utc))
        #expect(data.buckets.values.map(\.requests).reduce(0, +) == 2)
    }

    @Test func usageIsGroupedByDayModelAndProject() {
        var data = AgentUsageData()
        let yesterday = now.addingTimeInterval(-86_400 - 3600)
        data.add(record(at: now, identity: "1"), cwd: nil, now: now, calendar: utc)
        data.add(record(at: now, identity: "2", input: 4), cwd: nil, now: now, calendar: utc)
        data.add(record(at: now, identity: "3", model: "other"), cwd: nil, now: now, calendar: utc)
        data.add(record(at: now, identity: "4", cwd: "/x/else"), cwd: nil, now: now, calendar: utc)
        data.add(record(at: yesterday, identity: "5"), cwd: nil, now: now, calendar: utc)
        #expect(data.buckets.count == 4)
        let today = data.buckets.values.first {
            $0.day == UsageDay.key(now, calendar: utc) && $0.model == "m" && $0.project == "proj"
        }
        #expect(today?.tokens.input == 5 && today?.requests == 2)
    }

    @Test func olderThan91DaysIsPruned() {
        var data = AgentUsageData()
        let old = now.addingTimeInterval(-100 * 86_400)
        #expect(!data.add(record(at: old), cwd: nil, now: now, calendar: utc), "too old to count at all")
        let recent = now.addingTimeInterval(-90 * 86_400)
        #expect(data.add(record(at: recent, identity: "r"), cwd: nil, now: now, calendar: utc))
        data.prune(now: now.addingTimeInterval(5 * 86_400), calendar: utc)
        #expect(data.buckets.isEmpty && data.seen.isEmpty)
    }

    @Test func projectsAreTheFolderWithoutTheWorktree() {
        var data = AgentUsageData()
        data.add(
            record(at: now, cwd: "/Users/me/code/island/.claude/worktrees/feature"), cwd: nil, now: now, calendar: utc)
        #expect(data.buckets.values.first?.project == "island")
    }
}

/// The store on a temporary home folder with made-up logs.
struct AgentUsageStoreTests {
    private let now = Date()
    private let everything = AgentUsageRequest(readsClaude: true, readsCodex: true, threshold: 80)

    private func makeHome() -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func store(_ home: URL) -> AgentUsageStore {
        AgentUsageStore(home: home, cacheURL: home.appendingPathComponent("cache/usage.json"), calendar: utc)
    }

    private func write(_ lines: [String], to relative: String, in home: URL, append: Bool = false) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        if append, let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    private func tokens(_ snapshot: AgentUsageSnapshot) -> Int { snapshot.buckets.map(\.tokens.total).reduce(0, +) }

    @Test func aCopiedResponseInAnotherLogIsCountedOnce() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let line = claudeLine(at: now, id: "m1", request: "r1")
        try write([line], to: ".claude/projects/a/s1.jsonl", in: home)
        try write([line, claudeLine(at: now, id: "m2", request: "r2")], to: ".claude/projects/a/s2.jsonl", in: home)
        let snapshot = await store(home).refresh(everything, now: now)
        #expect(tokens(snapshot) == 60, "two responses of 30 tokens")
    }

    @Test func aResumedReadStartsAtTheOffset() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // No identity, so a second read from the start would count these again.
        let first = claudeLine(at: now, id: nil, request: nil)
        try write([first], to: ".claude/projects/a/s1.jsonl", in: home)
        let store = store(home)
        #expect(tokens(await store.refresh(everything, now: now)) == 30)
        #expect(tokens(await store.refresh(everything, now: now)) == 30, "nothing new, nothing counted")
        try write([claudeLine(at: now, id: nil, request: nil)], to: ".claude/projects/a/s1.jsonl", in: home, append: true)
        #expect(tokens(await store.refresh(everything, now: now)) == 60)
    }

    @Test func theCacheLetsTheNextLaunchResume() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write([claudeLine(at: now, id: nil, request: nil)], to: ".claude/projects/a/s1.jsonl", in: home)
        _ = await store(home).refresh(everything, now: now)
        let next = store(home)
        #expect(tokens(await next.refresh(everything, now: now)) == 30, "read from the cache, not twice")
        try write([claudeLine(at: now, id: nil, request: nil)], to: ".claude/projects/a/s1.jsonl", in: home, append: true)
        #expect(tokens(await next.refresh(everything, now: now)) == 60)
    }

    @Test func aRewrittenFileIsReadAgain() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = ".claude/projects/a/s1.jsonl"
        try write([claudeLine(at: now, id: nil, request: nil, output: 500)], to: path, in: home)
        let store = store(home)
        #expect(tokens(await store.refresh(everything, now: now)) == 510)
        // Shorter and different: a new file in the old one's place.
        try FileManager.default.removeItem(at: home.appendingPathComponent(path))
        try write([claudeLine(at: now, id: nil, request: nil, output: 1)], to: path, in: home)
        #expect(tokens(await store.refresh(everything, now: now.addingTimeInterval(120))) == 521)
    }

    @Test func codexRateLimitsAreRead() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let resets = now.addingTimeInterval(3 * 3600)
        let lines = [
            json(["type": "session_meta", "payload": ["id": "c1", "cwd": "/Users/me/code/site"]]),
            json(["type": "turn_context", "payload": ["model": "gpt-5-codex", "cwd": "/Users/me/code/site"]]),
            json([
                "type": "event_msg", "timestamp": iso(now),
                "payload": [
                    "type": "token_count",
                    "info": [
                        "last_token_usage": ["input_tokens": 1000, "cached_input_tokens": 400, "output_tokens": 50],
                        "total_token_usage": ["total_tokens": 1050],
                    ],
                    "rate_limits": [
                        "primary": [
                            "used_percent": 42.0, "window_minutes": 300, "resets_at": resets.timeIntervalSince1970,
                        ],
                        "secondary": ["used_percent": 10.0, "window_minutes": 10080, "resets_in_seconds": 86_400],
                    ],
                ],
            ]),
        ]
        try write(lines, to: ".codex/sessions/2026/10/01/rollout.jsonl", in: home)
        let snapshot = await store(home).refresh(everything, now: now)
        let session = try #require(snapshot.limit(.codex, .session))
        #expect(session.percent == 42 && session.resetsAt != nil)
        #expect(snapshot.limit(.codex, .week)?.percent == 10)
        let bucket = try #require(snapshot.buckets.first)
        #expect(bucket.agent == .codex && bucket.project == "site" && bucket.model == "gpt-5-codex")
        #expect(bucket.tokens == AgentTokens(input: 600, output: 50, cacheRead: 400))
    }

    @Test func turningOffDeletesTheCache() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write([claudeLine(at: now)], to: ".claude/projects/a/s1.jsonl", in: home)
        let store = store(home)
        _ = await store.refresh(everything, now: now)
        let cache = home.appendingPathComponent("cache/usage.json")
        #expect(FileManager.default.fileExists(atPath: cache.path))
        await store.clear()
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        // Nothing of it is left in memory either: the folder is read afresh.
        let snapshot = await store.refresh(everything, now: now)
        #expect(tokens(snapshot) == 30)
    }

    @Test func withoutTheFileItIsAnEstimate() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write([claudeLine(at: now.addingTimeInterval(-3600))], to: ".claude/projects/a/s1.jsonl", in: home)
        let snapshot = await store(home).refresh(everything, now: now)
        #expect(!snapshot.hasClaudePlanFile)
        let estimate = try #require(snapshot.limit(.claudeCode, .session))
        #expect(estimate.isEstimate && estimate.percent == nil && estimate.resetsAt != nil)
    }

    @Test func theLimitNoticeComesOncePerWindow() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let samples: [[String: Any]] = [
            ["t": now.addingTimeInterval(-600).timeIntervalSince1970 * 1000, "org": "o", "u": ["fh": 85.0, "sd": 20.0]]
        ]
        try Data(json(["version": 2, "samples": samples]).utf8).write(to: {
            let url = home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return url
        }())
        let store = store(home)
        let first = await store.refresh(everything, now: now)
        #expect(first.hasClaudePlanFile)
        #expect(first.newlyOver.map(\.kind) == [.session])
        let second = await store.refresh(everything, now: now.addingTimeInterval(30))
        #expect(second.newlyOver.isEmpty, "the same window is not announced again")
    }
}

struct AgentLimitTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ minutesAgo: Double, fh: Double?, sd: Double? = nil, org: String? = "o") -> ClaudePlanUsage.Sample {
        ClaudePlanUsage.Sample(
            time: now.addingTimeInterval(-minutesAgo * 60), organization: org, fiveHour: fh, sevenDay: sd)
    }

    private func limits(_ samples: [ClaudePlanUsage.Sample], org: String? = "o", firstRequest: Date? = nil) -> [AgentLimit] {
        ClaudePlanUsage.limits(samples: samples, organization: org, now: now, firstRequest: { _, _ in firstRequest })
    }

    @Test func theClaudeAppFileIsReadInBothVersions() throws {
        let t = now.timeIntervalSince1970
        let v2 = json(["version": 2, "samples": [["t": t * 1000, "org": "o", "u": ["fh": 12.0, "sd": 3.0]]]])
        let list = json(["history": [["timestamp": t, "orgId": "o", "usage": ["five_hour": 12.0, "seven_day": 3.0]]]])
        for text in [v2, list] {
            let samples = ClaudePlanUsage.samples(from: Data(text.utf8))
            #expect(samples.count == 1 && samples[0].fiveHour == 12 && samples[0].sevenDay == 3)
            #expect(samples[0].organization == "o")
        }
        #expect(ClaudePlanUsage.samples(from: Data("[]".utf8)).isEmpty)
        #expect(ClaudePlanUsage.samples(from: Data("garbage".utf8)).isEmpty)
    }

    @Test func onlyTheAccountsOrgCounts() {
        let samples = [sample(30, fh: 10, org: "other"), sample(5, fh: 40, org: "o"), sample(1, fh: 99, org: "other")]
        let result = limits(samples)
        #expect(result.first { $0.kind == .session }?.percent == 40)
        #expect(limits([sample(5, fh: 40, org: "other")]).isEmpty)
        let account = json(["oauthAccount": ["organizationUuid": "o", "emailAddress": "x@example.com"]])
        #expect(ClaudePlanUsage.organization(fromClaudeJSON: Data(account.utf8)) == "o")
    }

    @Test func sessionResetIsFiveHoursAfterTheRunStarted() throws {
        // Zero, then 10, 20, 30 over the last hour: the run began at the 10.
        let samples = [sample(90, fh: 0), sample(60, fh: 10), sample(30, fh: 20), sample(5, fh: 30)]
        let session = try #require(limits(samples).first { $0.kind == .session })
        #expect(session.percent == 30)
        #expect(session.resetsAt == now.addingTimeInterval(-60 * 60 + 5 * 3600))
        // A fall begins a new run.
        let fell = [sample(120, fh: 80), sample(60, fh: 5), sample(5, fh: 9)]
        let again = try #require(limits(fell).first { $0.kind == .session })
        #expect(again.resetsAt == now.addingTimeInterval(-60 * 60 + 5 * 3600))
        // The first request of the session narrows its start.
        let first = now.addingTimeInterval(-70 * 60)
        let narrowed = try #require(limits(samples, firstRequest: first).first { $0.kind == .session })
        #expect(narrowed.resetsAt == first.addingTimeInterval(5 * 3600))
    }

    @Test func aSessionReadingFromBeforeTheLastSessionIsDropped() {
        #expect(limits([sample(6 * 60, fh: 50)]).first { $0.kind == .session } == nil)
        // A run that began over five hours ago has already reset.
        let samples = [sample(5.5 * 60 - 1, fh: 10), sample(60, fh: 20), sample(10, fh: 30)]
        #expect(limits(samples).first { $0.kind == .session } == nil)
    }

    @Test func weeklyResetIsSevenDaysAfterTheDrop() throws {
        // The week fell from 80 to 2 two days ago, at some time between hours.
        let drop = now.addingTimeInterval(-2 * 86_400 + 1234)
        let samples = [
            ClaudePlanUsage.Sample(
                time: drop.addingTimeInterval(-600), organization: "o", fiveHour: 0, sevenDay: 80),
            ClaudePlanUsage.Sample(time: drop, organization: "o", fiveHour: 0, sevenDay: 2),
            sample(1, fh: 0, sd: 6),
        ]
        let week = try #require(limits(samples).first { $0.kind == .week })
        #expect(week.percent == 6)
        let expected = ((drop.timeIntervalSince1970 + 7 * 86_400) / 3600).rounded(.up) * 3600
        #expect(week.resetsAt == Date(timeIntervalSince1970: expected))
        #expect(limits([sample(1, fh: 0, sd: 6)]).first { $0.kind == .week }?.resetsAt == nil, "no drop, no reset time")
    }

    @Test func staleReadingsShowTheirAge() throws {
        let fresh = try #require(limits([sample(5, fh: 10, sd: 4)]).first)
        #expect(fresh.asOf == nil)
        let stale = try #require(limits([sample(45, fh: 10, sd: 4)]).first)
        #expect(stale.asOf == now.addingTimeInterval(-45 * 60))
        #expect(!stale.isOver(threshold: 5), "a stale reading is never announced")
        #expect(AgentUsageFormat.resetLine(stale, now: now).contains("as of"))
    }

    @Test func theEstimatedBlockStartsOnTheHourOfTheFirstRequest() throws {
        let hour = floor(now.timeIntervalSince1970 / 3600) * 3600
        let first = Date(timeIntervalSince1970: hour - 3600 + 600)
        let block = try #require(EstimatedBlock.current(requests: [first, first.addingTimeInterval(1200)], now: now))
        #expect(block.start == Date(timeIntervalSince1970: hour - 3600))
        #expect(block.end == block.start.addingTimeInterval(5 * 3600))
        #expect(EstimatedBlock.current(requests: [now.addingTimeInterval(-9 * 3600)], now: now) == nil)
        #expect(EstimatedBlock.current(requests: [], now: now) == nil)
    }

    @Test func codexWindowsAreSortedByLength() {
        let reading = CodexRateLimits(
            observed: now,
            primary: .init(usedPercent: 30, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600)),
            secondary: .init(usedPercent: 7, windowMinutes: 7 * 1440, resetsAt: now.addingTimeInterval(86_400)))
        let limits = CodexLimits.limits(from: reading, now: now)
        #expect(limits.map(\.kind) == [.session, .week])
        let odd = CodexRateLimits(
            observed: now, primary: .init(usedPercent: 30, windowMinutes: 2 * 1440, resetsAt: nil), secondary: nil)
        #expect(CodexLimits.limits(from: odd, now: now).isEmpty, "a window that is neither is left out")
        let past = CodexRateLimits(
            observed: now, primary: .init(usedPercent: 30, windowMinutes: 300, resetsAt: now.addingTimeInterval(-60)),
            secondary: nil)
        #expect(CodexLimits.limits(from: past, now: now).isEmpty, "a window that has reset says nothing")
    }
}

struct AgentActivityMapTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func bucket(daysAgo: Int, tokens: Int) -> UsageBucket {
        let date = utc.date(byAdding: .day, value: -daysAgo, to: now)!
        return UsageBucket(
            day: UsageDay.key(date, calendar: utc), agent: .claudeCode, model: "m", project: "p",
            tokens: AgentTokens(input: tokens), requests: 1)
    }

    @Test func heatmapStepsAreQuartiles() {
        let buckets = (1...8).map { bucket(daysAgo: $0 * 2, tokens: $0) }
        let map = ActivityMap.make(buckets: buckets, now: now, calendar: utc)
        let levels = Dictionary(
            uniqueKeysWithValues: map.weeks.flatMap { $0 }.filter { $0.tokens > 0 }.map { ($0.tokens, $0.level) })
        #expect(levels[1] == 1 && levels[2] == 1)
        #expect(levels[3] == 2 && levels[4] == 2)
        #expect(levels[5] == 3 && levels[6] == 3)
        #expect(levels[7] == 4 && levels[8] == 4)
        #expect(map.weeks.count == 13 && map.weeks.allSatisfy { $0.count == 7 })
        #expect(map.activeDays == 8)
    }

    @Test func theMapEndsWithTodayAndLeavesTheRestOfTheWeekEmpty() {
        let map = ActivityMap.make(buckets: [bucket(daysAgo: 0, tokens: 5)], now: now, calendar: utc)
        let cells = map.weeks.flatMap { $0 }
        let today = UsageDay.key(now, calendar: utc)
        let marked = cells.first { $0.date.map { UsageDay.key($0, calendar: utc) } == today }
        #expect(marked?.level == 1)
        #expect(cells.filter { $0.date == nil }.allSatisfy { $0.level == 0 })
        #expect(cells.contains { $0.date == nil } || utc.component(.weekday, from: now) == 1)
    }

    @Test func theStreakCountsDaysInARow() {
        let run = [0, 1, 2, 4].map { bucket(daysAgo: $0, tokens: 10) }
        #expect(ActivityMap.make(buckets: run, now: now, calendar: utc).streak == 3)
        // Nothing yet today keeps yesterday's streak alive.
        let yesterday = [1, 2].map { bucket(daysAgo: $0, tokens: 10) }
        #expect(ActivityMap.make(buckets: yesterday, now: now, calendar: utc).streak == 2)
        #expect(ActivityMap.make(buckets: [bucket(daysAgo: 3, tokens: 10)], now: now, calendar: utc).streak == 0)
        #expect(ActivityMap.make(buckets: [], now: now, calendar: utc).streak == 0)
    }

    @Test func theRangesCoverTheirDays() {
        let buckets = [0, 6, 7, 29, 30].map { bucket(daysAgo: $0, tokens: 1_000_000) }
        func total(_ range: UsageRange) -> Int {
            AgentUsageSummary.make(buckets: buckets, range: range, now: now, pricing: AgentPricing(), calendar: utc).tokens
        }
        #expect(total(.today) == 1_000_000)
        #expect(total(.week) == 2_000_000)
        #expect(total(.month) == 4_000_000)
    }

    @Test func rankingsPutTheBiggestFirst() {
        let day = UsageDay.key(now, calendar: utc)
        let buckets = [
            UsageBucket(day: day, agent: .claudeCode, model: "claude-opus-4-5-20251101", project: "a", tokens: AgentTokens(input: 1_000_000), requests: 1),
            UsageBucket(day: day, agent: .claudeCode, model: "claude-sonnet-4-5-20250929", project: "b", tokens: AgentTokens(input: 1_000_000), requests: 1),
        ]
        let summary = AgentUsageSummary.make(
            buckets: buckets, range: .today, now: now, pricing: price(""), calendar: utc)
        #expect(summary.models.map(\.name) == ["opus-4-5", "sonnet-4-5"])
        #expect(summary.projects.map(\.name) == ["a", "b"])
    }

    @Test func numbersAreWordedBriefly() {
        #expect(AgentUsageFormat.tokens(820) == "820" && AgentUsageFormat.tokens(12_400) == "12.4K")
        #expect(AgentUsageFormat.tokens(142_000_000) == "142M" && AgentUsageFormat.tokens(1_300_000_000) == "1.3B")
        #expect(AgentUsageFormat.dollars(4.2) == "$4.20" && AgentUsageFormat.dollars(128.4) == "$128")
        #expect(AgentUsageFormat.dollars(4.2, atLeast: true) == "at least $4.20")
        #expect(AgentUsageFormat.percent(62, showsLeft: false) == "62%")
        #expect(AgentUsageFormat.percent(62, showsLeft: true) == "38% left")
    }
}

@MainActor
struct AgentUsageModelTests {
    @Test func aModelThatIsOffNeverReadsAnything() async {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AgentUsageModel(
            store: AgentUsageStore(home: home, cacheURL: home.appendingPathComponent("c.json"), calendar: utc))
        await model.refresh()
        #expect(model.snapshot == nil && !model.isEnabled)
        model.activity()
        #expect(model.snapshot == nil)
    }

    @Test func turningTheFeatureOffForgetsTheHistory() {
        let activity = AgentActivity()
        activity.usage.show(PreviewSamples.usageSnapshot())
        #expect(activity.usage.snapshot != nil)
        activity.reset()
        #expect(activity.usage.snapshot == nil && !activity.usage.isEnabled)
    }

    @Test func theLimitNoticeIsWordedWithTheAgentAndTheTime() {
        let banner = Announcements.agentLimit(agent: .claudeCode, percent: 80, resetsAt: Date())
        #expect(banner.title == "Claude at 80%" && banner.detail?.hasPrefix("Resets at ") == true)
        #expect(banner.isAlert)
        #expect(Announcements.agentLimit(agent: .codex, percent: 90, resetsAt: nil).detail == nil)
        #expect(AmbientEvent.agentLimit.group == .agents)
    }

    @Test func theNewSettingsDefaultAndStayInRange() {
        let suite = "usage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.agentLimitThreshold == 80 && !settings.showsLimitsLeft)
        settings.agentLimitThreshold = 90
        settings.agentLimitThreshold = 33
        #expect(settings.agentLimitThreshold == 80, "a value that isn't an option is the default")
        settings.agentLimitThreshold = 75
        settings.showsLimitsLeft = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.agentLimitThreshold == 75 && reloaded.showsLimitsLeft)
    }

    @Test func theAgentsWidgetIsOfferedOnlyWithTheFeature() {
        let suite = "widget-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let widget = WidgetID.builtIn(.agents)
        settings.setOn(.agents, false)
        #expect(!settings.isWidgetAllowed(widget))
        settings.setOn(.agents, true)
        #expect(settings.isWidgetAllowed(widget))
        #expect(WidgetCatalog.feature(of: widget) == .agents)
    }

    @Test func aLongLineIsReadInChunks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("aaaa\nbbbb\ncccc\n".utf8).write(to: url)
        let first = AgentLogTail.read(url, from: 0, limit: 7)
        #expect(first?.lines == ["aaaa"] && first?.offset == 5)
        let rest = AgentLogTail.read(url, from: 5, limit: 100)
        #expect(rest?.lines == ["bbbb", "cccc"])
        let none = AgentLogTail.read(url, from: 0, limit: 3)
        #expect(none?.lines == [] && none?.offset == 0, "no newline in the chunk: nothing yet")
    }
}
