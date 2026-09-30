import Foundation
import Observation

/// What a custom widget last read.
struct WidgetValue: Equatable {
    var text: String
    var detail: String?
    var fetchedAt: Date
}

enum WidgetFetchError: LocalizedError, Equatable {
    case unsupported, badResponse, empty, tooSlow

    var errorDescription: String? {
        switch self {
        case .unsupported: "This widget doesn\u{2019}t fetch a value."
        case .badResponse: "The address didn\u{2019}t answer properly."
        case .empty: "There was nothing to show."
        case .tooSlow: "It took too long."
        }
    }
}

/// Reads a widget's source. Tests replace it; the Settings preview uses one that never runs anything.
protocol WidgetValueFetching: Sendable {
    func value(for source: CustomWidget.Source) async throws -> WidgetValue
}

/// The values of custom widgets, in memory only (like the clipboard and lyrics). The one automatic trigger is a
/// widget view's `.task`, so nothing is ever fetched while Home is hidden.
@MainActor
@Observable
final class CustomWidgetValues {
    enum Phase: Equatable {
        case idle, updating, failed(String)
    }

    private var values: [UUID: WidgetValue] = [:]
    private var phases: [UUID: Phase] = [:]

    @ObservationIgnored private let fetcher: WidgetValueFetching
    @ObservationIgnored private let now: () -> Date

    init(fetcher: WidgetValueFetching, now: @escaping () -> Date = Date.init) {
        self.fetcher = fetcher
        self.now = now
    }

    func value(for id: UUID) -> WidgetValue? { values[id] }

    func state(for id: UUID) -> Phase { phases[id] ?? .idle }

    /// Fetches only when there is no value or it is older than the widget's limit. Buttons never fetch.
    func refreshIfStale(_ widget: CustomWidget) {
        guard !widget.isButton, state(for: widget.id) != .updating else { return }
        if let value = values[widget.id],
            now().timeIntervalSince(value.fetchedAt)
                < TimeInterval(max(widget.maxAgeMinutes, CustomWidget.minimumMaxAge) * 60)
        {
            return
        }
        refresh(widget)
    }

    /// A click, or Test in the editor. At most one fetch per widget runs at a time.
    @discardableResult
    func refresh(_ widget: CustomWidget) -> Task<Void, Never>? {
        guard state(for: widget.id) != .updating else { return nil }
        phases[widget.id] = .updating
        let id = widget.id
        let source = widget.source
        return Task { [weak self, fetcher] in
            do {
                let value = try await fetcher.value(for: source)
                self?.values[id] = value
                self?.phases[id] = .idle
            } catch {
                self?.phases[id] = .failed(error.localizedDescription)
            }
        }
    }

    /// Forget a widget that was deleted.
    func forget(_ id: UUID) {
        values[id] = nil
        phases[id] = nil
    }
}

// MARK: The real fetcher

/// Reads a widget's source for real: `shortcuts run`, one HTTPS request, a folder listing, or a program.
struct LiveWidgetFetcher: WidgetValueFetching {
    static let shortcutTimeout: TimeInterval = 30
    static let commandTimeout: TimeInterval = 5
    static let outputLimit = 4096
    static let webTimeout: TimeInterval = 10
    static let webLimit = 256 * 1024

    var now: @Sendable () -> Date = { Date() }

    func value(for source: CustomWidget.Source) async throws -> WidgetValue {
        switch source {
        case .shortcut(let name, let showsResult):
            guard showsResult else { throw WidgetFetchError.unsupported }
            return try await shortcut(name)
        case .web(let url, let path):
            return try await web(url, path: path)
        case .folder(let path):
            return try await folder(path)
        case .command(let path):
            return try await command(path)
        }
    }

    private func result(_ text: String) throws -> WidgetValue {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty
        }
        guard let first = lines.first else { throw WidgetFetchError.empty }
        return WidgetValue(
            text: String(first.prefix(WebValue.maxLength)),
            detail: lines.dropFirst().first.map { String($0.prefix(80)) },
            fetchedAt: now())
    }

    // `shortcuts run NAME --output-path FILE --output-type public.plain-text`: no input is passed in.
    private func shortcut(_ name: String) async throws -> WidgetValue {
        try await Task.detached {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(
                "macisland-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: file) }
            let output = try BoundedProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/shortcuts"),
                arguments: ["run", name, "--output-path", file.path, "--output-type", "public.plain-text"],
                timeout: Self.shortcutTimeout, outputLimit: Self.outputLimit)
            if output.timedOut { throw WidgetFetchError.tooSlow }
            guard output.status == 0 else { throw WidgetFetchError.badResponse }
            let data = (try? Data(contentsOf: file).prefix(Self.outputLimit)).map { Data($0) } ?? Data()
            return try result(String(decoding: data, as: UTF8.self))
        }.value
    }

    private func command(_ path: String) async throws -> WidgetValue {
        try await Task.detached {
            let output = try BoundedProcess.run(
                executable: URL(fileURLWithPath: path), timeout: Self.commandTimeout, outputLimit: Self.outputLimit)
            if output.timedOut { throw WidgetFetchError.tooSlow }
            guard output.status == 0 else { throw WidgetFetchError.badResponse }
            return try result(output.text)
        }.value
    }

    private func folder(_ path: String) async throws -> WidgetValue {
        try await Task.detached {
            let url = URL(fileURLWithPath: path)
            let items = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            let newest = items.max {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (a ?? .distantPast) < (b ?? .distantPast)
            }
            return WidgetValue(
                text: items.count == 1 ? "1 item" : "\(items.count) items", detail: newest?.lastPathComponent,
                fetchedAt: now())
        }.value
    }

    // One GET: an ephemeral session (no cookies, no cache), a 10 s limit, and at most 256 KB.
    private func web(_ url: URL, path: String?) async throws -> WidgetValue {
        guard CustomWidget.isValidWebURL(url) else { throw WidgetFetchError.badResponse }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.webTimeout
        configuration.timeoutIntervalForResource = Self.webTimeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("MacIsland", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WidgetFetchError.badResponse }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count >= Self.webLimit { break }
        }
        guard let text = WebValue.extract(body, path: path) else { throw WidgetFetchError.empty }
        return WidgetValue(text: text, detail: nil, fetchedAt: now())
    }
}

/// For the Settings preview: a sample, and nothing ever runs.
struct SampleWidgetFetcher: WidgetValueFetching {
    func value(for source: CustomWidget.Source) async throws -> WidgetValue {
        WidgetValue(text: "42", detail: "Sample", fetchedAt: Date())
    }
}
