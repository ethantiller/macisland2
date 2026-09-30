import Foundation
import Observation
import SwiftUI

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

/// Synced lyrics in the LRC format: `[mm:ss.xx] words`.
enum LRC {
    /// Time-ordered lines. A line with several stamps becomes several lines; tags like `[ar:Artist]` are skipped.
    static func parse(_ source: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in source.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close]
                if let time = seconds(from: stamp) { times.append(time) }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { LyricLine(time: $0, text: text) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// The words being sung at `elapsed`, or `nil` before the first line and during instrumental gaps.
    static func text(at elapsed: TimeInterval, in lines: [LyricLine]) -> String? {
        guard let last = lines.last(where: { $0.time <= elapsed }), !last.text.isEmpty else { return nil }
        return last.text
    }

    private static func seconds(from stamp: Substring) -> TimeInterval? {
        let parts = stamp.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}

/// Finds and holds the synced lyrics for the current track, through LRCLIB. Off until the app turns it on.
@MainActor
@Observable
final class LyricsModel {
    private(set) var lines: [LyricLine] = []
    private(set) var isEnabled = false

    /// Replaced in tests.
    @ObservationIgnored var fetch: (URL) async -> Data? = LyricsModel.fetchFromNetwork
    @ObservationIgnored private var cache: [String: [LyricLine]] = [:]
    @ObservationIgnored private var currentKey: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func setEnabled(_ enabled: Bool, for state: NowPlayingState) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        currentKey = nil
        track(state)
    }

    /// Call whenever the now-playing state changes; work happens only when the track does.
    func track(_ state: NowPlayingState) {
        let key = Self.key(for: state)
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()

        guard isEnabled, state.hasMedia else { return show([]) }
        if let cached = cache[key] { return show(cached) }
        show([])
        guard let url = Self.url(for: state) else { return }
        task = Task { [weak self] in
            let data = await self?.fetch(url)
            guard !Task.isCancelled, let self else { return }
            let parsed = data.map(Self.lines(fromResponse:)) ?? []
            cache[key] = parsed
            if currentKey == key { show(parsed) }
        }
    }

    private func show(_ new: [LyricLine]) {
        guard new != lines else { return }
        withAnimation(Theme.Motion.resize) { lines = new }
    }

    nonisolated static func key(for state: NowPlayingState) -> String {
        "\(state.title)\u{1F}\(state.artist)\u{1F}\(state.album)\u{1F}\(Int(state.duration.rounded()))"
    }

    /// `GET /api/get`, which matches on name, artist, album, and length.
    nonisolated static func url(for state: NowPlayingState) -> URL? {
        guard !state.title.isEmpty, !state.artist.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: state.title),
            URLQueryItem(name: "artist_name", value: state.artist),
        ]
        if !state.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: state.album)) }
        if state.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(state.duration.rounded()))))
        }
        components?.queryItems = items
        return components?.url
    }

    nonisolated static func lines(fromResponse data: Data) -> [LyricLine] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let synced = object["syncedLyrics"] as? String
        else { return [] }
        return LRC.parse(synced)
    }

    private nonisolated static func fetchFromNetwork(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("MacIsland/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}
