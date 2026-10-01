import Foundation

// Claude Code and Codex keep a log of every session in the home folder. These are undocumented and can change with any release, so
// everything here is defensive: a line that doesn't decode is skipped, and what is expected is written down in one place.
//
// Claude Code: ~/.claude/projects/<project>/<session>.jsonl (and ~/.config/claude/projects). One JSON object per line. A "user" line
// that isn't meta or sidechain, and has text (not just tool results), starts a turn; an "assistant" line with a stop_reason of end_turn,
// stop_sequence, max_tokens, or refusal ends it; isApiErrorMessage ends it as a failure; a user line starting "[Request interrupted by
// user" ends it quietly. Subagent logs (<session>/subagents/*.jsonl) belong to their parent's turn.
// Codex: ~/.codex/sessions/**/*.jsonl. session_meta (id, cwd), turn_context (model), and event_msg with task_started, then
// task_complete or turn_aborted. Not checked on a Mac with Codex: **verify**.

/// Which tool wrote a log.
enum AgentKind: String, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case codex = "Codex"

    var id: Self { self }
}

/// What one log line says about a turn.
struct AgentLogEvent: Equatable {
    enum Outcome: Equatable {
        case finished, failed, interrupted
    }

    enum Kind: Equatable {
        case turnStarted
        case turnEnded(Outcome)
        /// Anything else: it shows the session is alive, and may carry its model or folder.
        case activity
    }

    var kind: Kind
    var sessionID: String?
    var cwd: String?
    var model: String?
    var date: Date?
}

enum AgentLogParser {
    /// The stop reasons that end a Claude Code turn.
    static let endingStopReasons: Set<String> = ["end_turn", "stop_sequence", "max_tokens", "refusal"]

    static func parse(_ line: String, agent: AgentKind) -> AgentLogEvent? {
        guard let data = line.data(using: .utf8), !data.isEmpty,
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        switch agent {
        case .claudeCode: return parseClaude(object)
        case .codex: return parseCodex(object)
        }
    }

    // MARK: Claude Code

    private static func parseClaude(_ object: [String: Any]) -> AgentLogEvent? {
        guard let type = object["type"] as? String else { return nil }
        var event = AgentLogEvent(
            kind: .activity, sessionID: object["sessionId"] as? String, cwd: object["cwd"] as? String,
            model: nil, date: date(object["timestamp"]))
        // A subagent's lines are its parent's activity, never its turn.
        let isSidechain = object["isSidechain"] as? Bool == true
        let message = object["message"] as? [String: Any]
        switch type {
        case "user":
            guard !isSidechain, object["isMeta"] as? Bool != true else { return event }
            let content = message?["content"]
            if interruptedText(in: content) {
                event.kind = .turnEnded(.interrupted)
            } else if hasPromptText(content) {
                event.kind = .turnStarted
            }
        case "assistant":
            event.model = message?["model"] as? String
            guard !isSidechain else { return event }
            if object["isApiErrorMessage"] as? Bool == true {
                event.kind = .turnEnded(.failed)
            } else if let reason = message?["stop_reason"] as? String, endingStopReasons.contains(reason) {
                event.kind = .turnEnded(.finished)
            }
        default:
            break
        }
        return event
    }

    /// Text the person typed: a string, or a list with a text item. A list of only tool results is the agent's own loop.
    private static func hasPromptText(_ content: Any?) -> Bool {
        if let text = content as? String { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let items = content as? [[String: Any]] else { return false }
        return items.contains { ($0["type"] as? String) == "text" }
    }

    private static func interruptedText(in content: Any?) -> Bool {
        func isInterruption(_ text: String) -> Bool { text.hasPrefix("[Request interrupted by user") }
        if let text = content as? String { return isInterruption(text) }
        guard let items = content as? [[String: Any]] else { return false }
        return items.contains { ($0["text"] as? String).map(isInterruption) ?? false }
    }

    // MARK: Codex

    private static func parseCodex(_ object: [String: Any]) -> AgentLogEvent? {
        guard let type = object["type"] as? String else { return nil }
        let payload = object["payload"] as? [String: Any]
        var event = AgentLogEvent(
            kind: .activity, sessionID: nil, cwd: payload?["cwd"] as? String, model: nil, date: date(object["timestamp"]))
        switch type {
        case "session_meta":
            event.sessionID = payload?["id"] as? String
        case "turn_context":
            event.model = payload?["model"] as? String
        case "event_msg":
            switch payload?["type"] as? String {
            case "task_started": event.kind = .turnStarted
            case "task_complete": event.kind = .turnEnded(.finished)
            case "turn_aborted": event.kind = .turnEnded(.interrupted)
            default: break
            }
        default:
            break
        }
        return event
    }

    // MARK: Helpers

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        if let text = value as? String { return withFraction.date(from: text) ?? plain.date(from: text) }
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds) }
        return nil
    }

    /// The folder a task is in, as a project name: its last component, without `/.claude/worktrees/<name>`.
    static func project(fromCwd cwd: String?) -> String {
        guard var path = cwd, !path.isEmpty else { return "Unknown" }
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "Unknown" : name
    }
}
