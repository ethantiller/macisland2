import CoreServices
import Foundation

/// The lines a log gained, parsed. Delivered on the main actor.
struct AgentLogBatch {
    var agent: AgentKind
    /// One session: the same for a session's log and its subagents'.
    var session: String
    var events: [AgentLogEvent]
}

/// Watches the logs and says what they gain. Behind a protocol so the activity is tested with lines pushed by hand.
@MainActor
protocol AgentLogWatching: AnyObject {
    /// Called with each batch of new lines, and with the sessions found in `~/.claude/sessions` (session to pid).
    var onBatch: ((AgentLogBatch) -> Void)? { get set }
    var onProcesses: (([String: Int32]) -> Void)? { get set }
    func start()
    func stop()
}

/// Reads the end of a file from an offset, whole lines only. Pure apart from the file, and tested on temporary files.
enum AgentLogTail {
    /// The complete lines after `offset`, and the offset after the last of them. A line still being written (no newline yet) waits
    /// for the next read. A file that got shorter was replaced: it is read from its start. With a `limit`, at most that many bytes are
    /// read, so a long file is taken in chunks; a chunk with no newline in it comes back empty at the same offset.
    static func read(_ url: URL, from offset: UInt64, limit: Int = .max) -> (lines: [String], offset: UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var start = offset
        if size < start { start = 0 }
        guard size > start else { return ([], size) }
        do { try handle.seek(toOffset: start) } catch { return nil }
        let data: Data?
        if limit == .max {
            data = try? handle.readToEnd()
        } else {
            data = try? handle.read(upToCount: limit)
        }
        guard let data, !data.isEmpty else { return ([], start) }
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], start) }
        let complete = data[data.startIndex...lastNewline]
        let lines = String(decoding: complete, as: UTF8.self).split(separator: "\n").map(String.init)
        return (lines, start + UInt64(complete.count))
    }
}

/// Where the logs are, and which session a log belongs to.
enum AgentLogLocations {
    static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [(url: URL, agent: AgentKind)] {
        [
            (home.appendingPathComponent(".claude/projects"), .claudeCode),
            (home.appendingPathComponent(".config/claude/projects"), .claudeCode),
            (home.appendingPathComponent(".codex/sessions"), .codex),
            (home.appendingPathComponent(".codex/archived_sessions"), .codex),
        ]
    }

    static func sessionsFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".claude/sessions")
    }

    /// The session a Claude Code log is part of: `<project>/<session>.jsonl`, or `<project>/<session>/subagents/<name>.jsonl`.
    static func claudeSession(forPath path: String) -> String {
        let parts = path.split(separator: "/")
        if let index = parts.lastIndex(of: "subagents"), index > 0 { return String(parts[index - 1]) }
        return ((parts.last.map(String.init) ?? path) as NSString).deletingPathExtension
    }

    /// The pids in `~/.claude/sessions/<pid>.json` files (`pid`, `sessionId`), by session.
    static func processes(in folder: URL) -> [String: Int32] {
        var result: [String: Int32] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let session = object["sessionId"] as? String, let pid = object["pid"] as? Int
            else { continue }
            result[session] = Int32(pid)
        }
        return result
    }
}

/// FSEvents on the log folders: pushed by the system, one stream, no polling. A changed file is read from where it was left, off the
/// main actor. It starts every file at its end (it never reads history), and a file it hasn't seen starts at its beginning.
@MainActor
final class AgentLogWatcher: AgentLogWatching {
    var onBatch: ((AgentLogBatch) -> Void)?
    var onProcesses: (([String: Int32]) -> Void)?

    private let home: URL
    private let queue = DispatchQueue(label: "com.ethantiller.MacIsland.agentlogs", qos: .utility)
    private var stream: FSEventStreamRef?
    /// Touched only on `queue`.
    private final class State: @unchecked Sendable {
        var offsets: [String: UInt64] = [:]
        var sessions: [String: String] = [:]
    }
    private let state = State()

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func start() {
        guard stream == nil else { return }
        let roots = AgentLogLocations.roots(home: home)
        let folders = roots.map(\.url) + [AgentLogLocations.sessionsFolder(home: home)]
        let existing = folders.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.path)
        guard !existing.isEmpty else { return }

        // Every file that is there now starts at its end.
        let state = state
        let rootList = roots
        queue.async {
            for root in rootList {
                guard let walker = FileManager.default.enumerator(
                    at: root.url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                else { continue }
                for case let url as URL in walker where url.pathExtension == "jsonl" {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    state.offsets[url.path] = UInt64(size)
                }
            }
        }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<AgentLogWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.changed(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        // The sessions that are open now.
        let sessions = AgentLogLocations.sessionsFolder(home: home)
        queue.async { [weak self] in
            let found = AgentLogLocations.processes(in: sessions)
            Task { @MainActor in self?.onProcesses?(found) }
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        let state = state
        queue.async {
            state.offsets = [:]
            state.sessions = [:]
        }
    }

    /// Called on `queue` by the stream.
    nonisolated private func changed(_ paths: [String]) {
        let home = home
        let sessionsFolder = AgentLogLocations.sessionsFolder(home: home).path
        let roots = AgentLogLocations.roots(home: home)
        var sawSessions = false
        for path in paths {
            if path.hasPrefix(sessionsFolder) {
                sawSessions = true
            } else if path.hasSuffix(".jsonl"), let agent = roots.first(where: { path.hasPrefix($0.url.path) })?.agent {
                read(path, agent: agent)
            }
        }
        if sawSessions {
            let found = AgentLogLocations.processes(in: URL(fileURLWithPath: sessionsFolder))
            Task { @MainActor [weak self] in self?.onProcesses?(found) }
        }
    }

    nonisolated private func read(_ path: String, agent: AgentKind) {
        let known = state.offsets[path]
        guard let tail = AgentLogTail.read(URL(fileURLWithPath: path), from: known ?? 0) else { return }
        state.offsets[path] = tail.offset
        guard !tail.lines.isEmpty else { return }
        let events = tail.lines.compactMap { AgentLogParser.parse($0, agent: agent) }
        guard !events.isEmpty else { return }
        // A Codex log names its session in its first line; until it has, the file is the session.
        var session = agent == .claudeCode ? AgentLogLocations.claudeSession(forPath: path) : (state.sessions[path] ?? path)
        if agent == .codex, let id = events.compactMap(\.sessionID).first {
            state.sessions[path] = id
            session = id
        }
        let batch = AgentLogBatch(agent: agent, session: session, events: events)
        Task { @MainActor [weak self] in self?.onBatch?(batch) }
    }
}

extension AgentLogLocations {
    /// Whether any agent has left a log folder here: without one, the module says it couldn't find them.
    static func hasLogs() -> Bool {
        roots().contains { FileManager.default.fileExists(atPath: $0.url.path) }
    }
}
