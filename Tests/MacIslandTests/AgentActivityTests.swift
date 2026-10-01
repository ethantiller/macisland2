import Foundation
import Testing

@testable import MacIsland

@MainActor
struct AgentActivityTests {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
    }

    private func claude(_ line: String) -> AgentLogEvent? { AgentLogParser.parse(line, agent: .claudeCode) }

    // MARK: Claude Code lines (shapes copied from real logs; the text is made up)

    @Test func aUserLineStartsATurnAndEndTurnEndsIt() {
        let prompt = line([
            "type": "user", "sessionId": "s1", "cwd": "/Users/me/code/island", "timestamp": "2026-10-01T10:00:00.000Z",
            "message": ["role": "user", "content": "fix the build"],
        ])
        let started = claude(prompt)
        #expect(started?.kind == .turnStarted && started?.sessionID == "s1" && started?.cwd == "/Users/me/code/island")
        #expect(started?.date != nil)

        let working = line([
            "type": "assistant", "sessionId": "s1",
            "message": ["model": "claude-opus-4-5-20251101", "stop_reason": "tool_use", "content": []],
        ])
        #expect(claude(working)?.kind == .activity && claude(working)?.model == "claude-opus-4-5-20251101")

        for reason in ["end_turn", "stop_sequence", "max_tokens", "refusal"] {
            let done = line(["type": "assistant", "message": ["stop_reason": reason, "model": "m"]])
            #expect(claude(done)?.kind == .turnEnded(.finished), reason)
        }
        let nullReason = line(["type": "assistant", "message": ["stop_reason": NSNull(), "model": "m"]])
        #expect(claude(nullReason)?.kind == .activity)
    }

    @Test func metaAndSidechainLinesDontStartATurn() {
        let meta = line(["type": "user", "isMeta": true, "message": ["content": "caveat"]])
        #expect(claude(meta)?.kind == .activity)
        let sidechain = line(["type": "user", "isSidechain": true, "message": ["content": "subtask"]])
        #expect(claude(sidechain)?.kind == .activity)
        // A tool's result is the agent's own loop, not a prompt.
        let result = line(["type": "user", "message": ["content": [["type": "tool_result", "content": "ok"]]]])
        #expect(claude(result)?.kind == .activity)
        // A list with text is a prompt.
        let typed = line(["type": "user", "message": ["content": [["type": "text", "text": "hello"]]]])
        #expect(claude(typed)?.kind == .turnStarted)
        // A subagent finishing is not its parent finishing.
        let subagentEnd = line(["type": "assistant", "isSidechain": true, "message": ["stop_reason": "end_turn"]])
        #expect(claude(subagentEnd)?.kind == .activity)
    }

    @Test func anInterruptionEndsQuietly() {
        let text = line(["type": "user", "message": ["content": [["type": "text", "text": "[Request interrupted by user]"]]]])
        #expect(claude(text)?.kind == .turnEnded(.interrupted))
        let string = line(["type": "user", "message": ["content": "[Request interrupted by user for tool use]"]])
        #expect(claude(string)?.kind == .turnEnded(.interrupted))
    }

    @Test func anAPIErrorEndsAsAFailureWithNoNotice() {
        let error = line(["type": "assistant", "isApiErrorMessage": true, "message": ["stop_reason": "stop_sequence"]])
        #expect(claude(error)?.kind == .turnEnded(.failed))

        let activity = AgentActivity(clock: { self.now })
        activity.minimumDuration = { 0 }
        var finished = 0
        activity.onFinish = { _, _ in finished += 1 }
        activity.ingest(.init(kind: .turnStarted, date: now.addingTimeInterval(-120)), agent: .claudeCode, session: "s")
        activity.ingest(.init(kind: .turnEnded(.failed), date: now), agent: .claudeCode, session: "s")
        #expect(finished == 0 && activity.liveTasks.isEmpty)
    }

    @Test func aBadLineIsSkipped() {
        #expect(claude("not json") == nil)
        #expect(claude("") == nil)
        #expect(claude("[1,2]") == nil)
        #expect(claude(#"{"no":"type"}"#) == nil)
        #expect(claude(#"{"type":"summary"}"#)?.kind == .activity, "an unknown type is only activity")
    }

    // MARK: Codex

    @Test func codexTaskStartedAndCompleteBracketATurn() {
        func codex(_ object: [String: Any]) -> AgentLogEvent? { AgentLogParser.parse(line(object), agent: .codex) }
        let meta = codex(["type": "session_meta", "payload": ["id": "c1", "cwd": "/Users/me/work/api"]])
        #expect(meta?.sessionID == "c1" && meta?.cwd == "/Users/me/work/api" && meta?.kind == .activity)
        #expect(codex(["type": "turn_context", "payload": ["model": "gpt-5"]])?.model == "gpt-5")
        #expect(codex(["type": "event_msg", "payload": ["type": "task_started"]])?.kind == .turnStarted)
        #expect(codex(["type": "event_msg", "payload": ["type": "task_complete"]])?.kind == .turnEnded(.finished))
        #expect(codex(["type": "event_msg", "payload": ["type": "turn_aborted"]])?.kind == .turnEnded(.interrupted))
        #expect(codex(["type": "event_msg", "payload": ["type": "agent_message"]])?.kind == .activity)
    }

    // MARK: Names

    @Test func theProjectIsTheLastFolderWithoutWorktrees() {
        #expect(AgentLogParser.project(fromCwd: "/Users/me/code/island") == "island")
        #expect(AgentLogParser.project(fromCwd: "/Users/me/code/island/.claude/worktrees/pensive-hopper") == "island")
        #expect(AgentLogParser.project(fromCwd: nil) == "Unknown")
        #expect(AgentLogParser.project(fromCwd: "") == "Unknown")
        let task = AgentTask(
            id: "s", agent: .claudeCode, project: "island", model: "claude-opus-4-5-20251101", startedAt: now,
            lastActivity: now)
        #expect(task.modelName == "opus-4-5" && task.subtitle == "Claude Code, opus-4-5")
    }

    @Test func theSessionIsTheLogsOrItsParents() {
        #expect(AgentLogLocations.claudeSession(forPath: "/h/.claude/projects/p/abc-123.jsonl") == "abc-123")
        #expect(AgentLogLocations.claudeSession(forPath: "/h/.claude/projects/p/abc-123/subagents/agent-9.jsonl") == "abc-123")
    }

    // MARK: Turns

    private func activity() -> AgentActivity {
        let activity = AgentActivity(clock: { self.now })
        activity.minimumDuration = { 60 }
        return activity
    }

    private func start(_ activity: AgentActivity, _ session: String = "s", at offset: TimeInterval = 0) {
        activity.ingest(
            .init(kind: .turnStarted, cwd: "/Users/me/code/island", model: "m", date: now.addingTimeInterval(offset)),
            agent: .claudeCode, session: session)
    }

    @Test func aSubagentBelongsToItsParent() {
        let activity = activity()
        start(activity, "parent", at: -100)
        // A subagent's lines arrive under the parent's session: they keep it alive, and don't start another turn.
        activity.ingest(.init(kind: .activity, date: now.addingTimeInterval(-10)), agent: .claudeCode, session: "parent")
        #expect(activity.liveTasks.count == 1 && activity.liveTasks[0].lastActivity == now.addingTimeInterval(-10))
    }

    @Test func aTurnQuietForTenMinutesStopsShowingAndALaterLineResumesIt() {
        var clockNow = now
        let activity = AgentActivity(clock: { clockNow })
        activity.ingest(.init(kind: .turnStarted, date: clockNow), agent: .claudeCode, session: "s")
        #expect(activity.liveTasks.count == 1)
        clockNow = clockNow.addingTimeInterval(AgentActivity.idleLimit + 1)
        #expect(activity.liveTasks.isEmpty, "no line for ten minutes")
        activity.ingest(.init(kind: .activity, date: clockNow), agent: .claudeCode, session: "s")
        #expect(activity.liveTasks.count == 1, "a later line shows it again")
    }

    @Test func aDeadSessionEndsItsTurnQuietly() {
        let activity = activity()
        activity.minimumDuration = { 0 }
        var finished = 0
        activity.onFinish = { _, _ in finished += 1 }
        start(activity, "gone", at: -300)
        start(activity, "alive", at: -300)
        activity.setProcesses(["gone": 111, "alive": 222])
        activity.endTurnsOfDeadSessions(isAlive: { $0 == 222 })
        #expect(activity.liveTasks.map(\.id) == ["alive"] && finished == 0)
        // A turn whose process isn't known stays.
        start(activity, "unknown")
        activity.endTurnsOfDeadSessions(isAlive: { _ in false })
        #expect(activity.liveTasks.map(\.id) == ["unknown"])
    }

    @Test func theFinishNoticeNeedsTheMinimumAndARecentEnd() {
        let activity = activity()
        var notices: [(String, TimeInterval)] = []
        activity.onFinish = { task, duration in notices.append((task.project, duration)) }

        // Long enough and just ended: a notice, with how long it took.
        start(activity, "a", at: -252)
        activity.ingest(.init(kind: .turnEnded(.finished), date: now), agent: .claudeCode, session: "a")
        #expect(notices.count == 1 && notices[0].0 == "island" && notices[0].1 == 252)

        // Too short.
        start(activity, "b", at: -30)
        activity.ingest(.init(kind: .turnEnded(.finished), date: now), agent: .claudeCode, session: "b")
        #expect(notices.count == 1)

        // Ended more than five minutes ago.
        start(activity, "c", at: -2000)
        activity.ingest(.init(kind: .turnEnded(.finished), date: now.addingTimeInterval(-400)), agent: .claudeCode, session: "c")
        #expect(notices.count == 1)

        // Interrupted or failed.
        start(activity, "d", at: -252)
        activity.ingest(.init(kind: .turnEnded(.interrupted), date: now), agent: .claudeCode, session: "d")
        #expect(notices.count == 1)

        // The minimum is read when the turn ends.
        activity.minimumDuration = { 300 }
        start(activity, "e", at: -252)
        activity.ingest(.init(kind: .turnEnded(.finished), date: now), agent: .claudeCode, session: "e")
        #expect(notices.count == 1)
        activity.minimumDuration = { 30 }
        start(activity, "f", at: -40)
        activity.ingest(.init(kind: .turnEnded(.finished), date: now), agent: .claudeCode, session: "f")
        #expect(notices.count == 2)
    }

    @Test func theFirstReadAnnouncesNothing() {
        let activity = activity()
        var finished = 0
        activity.onFinish = { _, _ in finished += 1 }
        start(activity, "old", at: -252)
        activity.ingest(.init(kind: .turnEnded(.finished), date: now), agent: .claudeCode, session: "old", announces: false)
        #expect(finished == 0)
    }

    @Test func aModelLearnedBeforeTheTurnIsUsed() {
        let activity = activity()
        activity.ingest(
            .init(kind: .activity, cwd: "/w/api", model: "gpt-5", date: now), agent: .codex, session: "c")
        activity.ingest(.init(kind: .turnStarted, date: now), agent: .codex, session: "c")
        #expect(activity.liveTasks.first?.model == "gpt-5" && activity.liveTasks.first?.project == "api")
    }

    // MARK: On the island

    @Test func theAgentRanksRightAfterWorking() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.agents, true)
        viewModel.agents.ingest(.init(kind: .turnStarted, date: Date()), agent: .claudeCode, session: "s")
        #expect(viewModel.compactActivities == [.agent])
        let job = viewModel.features.work.begin("Zipping")
        #expect(viewModel.compactActivities == [.working("Zipping"), .agent])
        viewModel.features.work.end(job)
        var song = NowPlayingState()
        song.title = "Song"
        song.isPlaying = true
        song.playbackRate = 1
        song.duration = 200
        song.timestamp = Date()
        viewModel.nowPlaying.apply(song)
        #expect(viewModel.compactActivities == [.agent, .media])
        viewModel.settings.showsAgentCompact = false
        #expect(viewModel.compactActivities == [.media], "the option")
        viewModel.settings.showsAgentCompact = true
        viewModel.settings.setOn(.agents, false)
        #expect(viewModel.compactActivities == [.media], "the feature")
    }

    @Test func aClickOnTheAgentOpensAgents() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.agents, true)
        viewModel.agents.ingest(.init(kind: .turnStarted, date: Date()), agent: .claudeCode, session: "s")
        viewModel.tapCompact()
        #expect(viewModel.state == .expanded && viewModel.selectedTab == .agents)
    }

    @Test func turningAgentsOffStopsTheStream() {
        let viewModel = TestSupport.makeViewModel()
        var started: [Bool] = []
        let runner = FeatureRunner(
            features: viewModel.features, viewModel: viewModel, music: { _ in }, screenshots: { _ in },
            agents: { started.append($0) })
        viewModel.settings.onFeatureChange = { runner.apply($0) }
        viewModel.settings.setOn(.agents, true)
        viewModel.agents.ingest(.init(kind: .turnStarted, date: Date()), agent: .claudeCode, session: "s")
        #expect(started == [true] && viewModel.agents.liveTasks.count == 1)
        viewModel.settings.setOn(.agents, false)
        #expect(started == [true, false] && viewModel.agents.liveTasks.isEmpty, "stopped and forgotten")
        // Launch starts it only when it is on.
        runner.startAtLaunch()
        #expect(started == [true, false])
    }

    @Test func atLeastOneAgentStaysOnAndTheOptionsTravel() throws {
        let name = "MacIslandAgents.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.reads(.claudeCode) && settings.reads(.codex) && settings.showsAgentCompact)
        #expect(settings.agentFinishMinimum == 60)
        settings.setReads(.codex, false)
        settings.setReads(.claudeCode, false)
        #expect(!settings.reads(.codex) && settings.reads(.claudeCode), "the last one stays")
        settings.agentFinishMinimum = 120
        settings.agentFinishMinimum = 7
        #expect(settings.agentFinishMinimum == 60, "a value that isn't an option is the default")
        settings.agentFinishMinimum = 120

        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.reads(.codex) && reloaded.agentFinishMinimum == 120)
        let target = AppSettings(defaults: UserDefaults(suiteName: name + "2")!)
        target.restore(try SettingsArchive.read(SettingsArchive.make(from: settings).data()))
        #expect(!target.reads(.codex) && target.reads(.claudeCode) && target.agentFinishMinimum == 120)

        // Neither stored as on reads as both on.
        defaults.set(false, forKey: "agents.claude")
        defaults.set(false, forKey: "agents.codex")
        let both = AppSettings(defaults: defaults)
        #expect(both.reads(.claudeCode) && both.reads(.codex))
    }

    @Test func theNoticeIsAnEventOnlyShownWhileAgentsIsOn() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "MacIslandAgentEvent.\(UUID().uuidString)")!)
        #expect(AmbientEvent.agentDone.group == .agents)
        #expect(NotificationsPane.requirement(for: .agentDone, settings: settings) == "Turn on AI Agents in Features.")
        settings.setOn(.agents, true)
        #expect(NotificationsPane.requirement(for: .agentDone, settings: settings) == nil)
        let alert = Announcements.agentDone(duration: 252)
        #expect(alert.text == "Done 4:12" && alert.systemImage == "sparkles")
    }
}

@MainActor
struct AgentTailTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
    }

    private func append(_ text: String, to url: URL) throws {
        if let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    @Test func onlyTheTailIsRead() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try append("one\ntwo\n", to: url)
        let size = UInt64(8)
        // Starting at the end reads nothing of the history.
        #expect(AgentLogTail.read(url, from: size)?.lines == [])
        try append("three\nfour\n", to: url)
        let tail = AgentLogTail.read(url, from: size)
        #expect(tail?.lines == ["three", "four"] && tail?.offset == 19)
    }

    @Test func aLineStillBeingWrittenWaits() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try append("done\npart", to: url)
        let first = AgentLogTail.read(url, from: 0)
        #expect(first?.lines == ["done"] && first?.offset == 5)
        try append("ial\n", to: url)
        let second = AgentLogTail.read(url, from: first?.offset ?? 0)
        #expect(second?.lines == ["partial"])
    }

    @Test func aFileThatGotShorterIsReadFromItsStart() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("replaced\n".utf8).write(to: url)
        #expect(AgentLogTail.read(url, from: 500)?.lines == ["replaced"])
        #expect(AgentLogTail.read(URL(fileURLWithPath: "/nonexistent/x.jsonl"), from: 0) == nil)
    }

    @Test func theSessionsFolderGivesProcesses() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"pid": 4242, "sessionId": "abc", "cwd": "/x", "status": "busy"}"#.utf8)
            .write(to: folder.appendingPathComponent("4242.json"))
        try Data("garbage".utf8).write(to: folder.appendingPathComponent("1.json"))
        #expect(AgentLogLocations.processes(in: folder) == ["abc": 4242])
    }
}
