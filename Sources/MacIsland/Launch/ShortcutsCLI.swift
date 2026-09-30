import Foundation

/// Apple Shortcuts, through the `shortcuts` command that ships with macOS.
enum ShortcutsCLI {
    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// One name per line, blank lines dropped, in name order.
    nonisolated static func parse(listOutput: String) -> [String] {
        listOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func list() async -> [String] {
        await Task.detached { () -> [String] in
            guard let output = run(["list"]) else { return [] }
            return parse(listOutput: output.text)
        }.value
    }

    /// Runs a shortcut by name and waits for it. `true` if it finished without an error.
    static func run(shortcut name: String) async -> Bool {
        await Task.detached { run(["run", name])?.succeeded ?? false }.value
    }

    private nonisolated static func run(_ arguments: [String]) -> (text: String, succeeded: Bool)? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus == 0)
    }
}
