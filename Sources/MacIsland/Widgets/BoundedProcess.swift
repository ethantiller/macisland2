import Foundation

/// Runs one program with no shell, no arguments unless given, no input, a minimal environment, a time limit, and
/// a cap on what it may say. Used for command widgets and for reading a Shortcut's result.
enum BoundedProcess {
    struct Output: Equatable {
        var text: String
        var status: Int32
        var timedOut: Bool
    }

    enum RunError: LocalizedError, Equatable {
        case notExecutable, couldNotStart
        var errorDescription: String? {
            switch self {
            case .notExecutable: "That file can\u{2019}t be run."
            case .couldNotStart: "It didn\u{2019}t start."
            }
        }
    }

    static let minimalEnvironment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
    ]

    /// Blocking: call it off the main thread. On a timeout the process gets a terminate, and a kill a second later.
    nonisolated static func run(
        executable: URL, arguments: [String] = [], timeout: TimeInterval, outputLimit: Int,
        environment: [String: String] = minimalEnvironment
    ) throws -> Output {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw RunError.notExecutable }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let collector = Collector(limit: outputLimit)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else if collector.add(chunk) {
                // It said enough: stop listening, and stop it.
                handle.readabilityHandler = nil
                if process.isRunning { process.terminate() }
            }
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw RunError.couldNotStart }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        // Whatever was written just before it ended.
        if let rest = try? pipe.fileHandleForReading.readToEnd(), !rest.isEmpty { _ = collector.add(rest) }
        return Output(text: collector.text, status: process.terminationStatus, timedOut: timedOut)
    }

    /// Output gathered from a background thread, held to a limit.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        /// Returns true once the limit is reached.
        func add(_ chunk: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk.prefix(max(limit - data.count, 0)))
            return data.count >= limit
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
