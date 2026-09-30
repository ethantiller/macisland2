import Foundation

/// Talks to MediaRemote through the bundled mediaremote-adapter. Since macOS 15.4 only
/// Apple-entitled binaries may use MediaRemote, so the adapter runs inside /usr/bin/perl.
@MainActor
final class MediaRemoteAdapter {
    enum Command: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    var onState: ((NowPlayingState) -> Void)?

    private let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private let script: URL
    private let framework: URL
    private var streamProcess: Process?
    private var readTask: Task<Void, Never>?
    private var isStopped = true

    init?(bundle: Bundle = .main) {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = bundle.privateFrameworksURL?
                  .appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        self.script = script
        self.framework = framework
    }

    func start() {
        isStopped = false
        launchStream()
    }

    func stop() {
        isStopped = true
        readTask?.cancel()
        streamProcess?.terminate()
        streamProcess = nil
    }

    func send(_ command: Command) {
        run(["send", String(command.rawValue)])
    }

    /// 1 is off, 3 is on for every track.
    func setShuffle(_ mode: Int) {
        run(["shuffle", String(mode)])
    }

    func setRepeat(_ mode: RepeatMode) {
        run(["repeat", String(mode.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        run(["seek", String(Int64(max(seconds, 0) * 1_000_000))])
    }

    private func launchStream() {
        let process = Process()
        process.executableURL = perl
        process.arguments = [script.path, framework.path, "stream", "--micros", "--debounce=50"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamDidExit() }
        }

        do {
            try process.run()
        } catch {
            streamDidExit()
            return
        }
        streamProcess = process

        let handle = pipe.fileHandleForReading
        readTask = Task.detached { [weak self] in
            var parser = NowPlayingStreamParser()
            do {
                for try await line in handle.bytes.lines {
                    guard let state = parser.consume(line: Data(line.utf8)) else { continue }
                    await self?.deliver(state)
                }
            } catch {}
        }
    }

    private func deliver(_ state: NowPlayingState) {
        onState?(state)
    }

    private func streamDidExit() {
        streamProcess = nil
        guard !isStopped else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.isStopped, self.streamProcess == nil else { return }
            self.launchStream()
        }
    }

    private func run(_ arguments: [String]) {
        let process = Process()
        process.executableURL = perl
        process.arguments = [script.path, framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
