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
enum AgentKind: String, CaseIterable, Identifiable, Codable {
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
    /// What the request cost, when the line is one (Claude's `message.usage`, Codex's `last_token_usage`).
    var tokens: AgentTokens?
    /// What makes two lines the same streamed response: a response is written more than once, and counts once.
    var messageID: String?
    /// How much of the model's context the request filled, and how much there is.
    var contextTokens: Int?
    var contextWindow: Int?
    /// What the person asked, on one line: the task's title.
    var prompt: String?
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
                event.prompt = promptLine(in: content)
            }
        case "assistant":
            event.model = message?["model"] as? String
            if let usage = message?["usage"] as? [String: Any] {
                let tokens = AgentTokens(claudeUsage: usage)
                if tokens.total > 0 {
                    event.tokens = tokens
                    event.contextTokens = tokens.contextUsed
                    event.contextWindow = claudeWindow(model: event.model, context: tokens.contextUsed)
                    if let id = message?["id"] as? String {
                        event.messageID = id + ":" + ((object["requestId"] as? String) ?? "")
                    }
                }
            }
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

    /// Claude Code's window: a million tokens for a model marked `[1m]` (or a context already past 200K), else 200K.
    static func claudeWindow(model: String?, context: Int) -> Int {
        (model?.contains("[1m]") == true || context > 200_000) ? 1_000_000 : 200_000
    }

    /// The first text that is the person's own words (not a command or system note, which start with "<"), on one line, at most 80
    /// characters.
    static func promptLine(in content: Any?) -> String? {
        var texts: [String] = []
        if let text = content as? String {
            texts = [text]
        } else if let items = content as? [[String: Any]] {
            texts = items.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
        }
        for text in texts {
            let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !line.isEmpty, !line.hasPrefix("<") else { continue }
            return line.count > 80 ? String(line.prefix(79)) + "\u{2026}" : line
        }
        return nil
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
            case "user_message":
                event.prompt = promptLine(in: payload?["message"])
            case "token_count":
                if let info = payload?["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any] {
                    func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
                    let input = int(last["input_tokens"])
                    let cached = min(int(last["cached_input_tokens"]), input)
                    let tokens = AgentTokens(input: input - cached, output: int(last["output_tokens"]), cacheRead: cached)
                    if tokens.total > 0 {
                        event.tokens = tokens
                        event.contextTokens = input
                        event.contextWindow = (info["model_context_window"] as? NSNumber)?.intValue
                    }
                }
            default: break
            }
        default:
            break
        }
        return event
    }

    // MARK: Helpers

    /// "Opus 4.5" from "claude-opus-4-5-20251101", and "GPT-5 Codex" from "gpt-5-codex".
    static func prettyModel(_ model: String) -> String {
        var name = model
        if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
        if name.hasPrefix("claude-") { name.removeFirst("claude-".count) }
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(range) }
        let parts = name.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return model }
        if parts[0].lowercased() == "gpt" {
            let rest = parts.dropFirst().map { $0.first?.isNumber == true ? $0 : $0.capitalized }
            guard let first = rest.first else { return "GPT" }
            return (["GPT-" + first] + rest.dropFirst()).joined(separator: " ")
        }
        let words = parts.filter { $0.first?.isLetter == true }.map(\.capitalized)
        let numbers = parts.filter { $0.first?.isNumber == true }
        return (words + (numbers.isEmpty ? [] : [numbers.joined(separator: ".")])).joined(separator: " ")
    }

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
