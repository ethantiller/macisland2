import Foundation

/// How the player repeats, as MediaRemote numbers it.
enum RepeatMode: Int {
    case off = 1
    case track = 2
    case playlist = 3

    /// Off, then the whole list, then one track, then off again.
    var next: RepeatMode {
        switch self {
        case .off: .playlist
        case .playlist: .track
        case .track: .off
        }
    }
}

struct NowPlayingState: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var bundleIdentifier: String?
    var isPlaying = false
    var playbackRate: Double = 0
    var duration: TimeInterval = 0
    /// Elapsed time as of `timestamp`; use `elapsed(at:)` for the live position.
    var elapsedTime: TimeInterval = 0
    var timestamp: Date?
    var artworkBase64: String?
    /// MediaRemote's shuffle mode: 1 is off, 2 albums, 3 tracks.
    var shuffleMode = 1
    var repeatMode = RepeatMode.off

    var hasMedia: Bool { !title.isEmpty }

    var isShuffling: Bool { shuffleMode > 1 }

    func elapsed(at date: Date) -> TimeInterval {
        guard isPlaying, let timestamp else { return clamp(elapsedTime) }
        let rate = playbackRate > 0 ? playbackRate : 1
        return clamp(elapsedTime + date.timeIntervalSince(timestamp) * rate)
    }

    private func clamp(_ time: TimeInterval) -> TimeInterval {
        duration > 0 ? min(max(time, 0), duration) : max(time, 0)
    }
}

extension NowPlayingState {
    /// Builds state from an adapter payload produced with `--micros`.
    init(payload: [String: Any]) {
        title = payload["title"] as? String ?? ""
        artist = payload["artist"] as? String ?? ""
        album = payload["album"] as? String ?? ""
        bundleIdentifier = payload["bundleIdentifier"] as? String
        isPlaying = payload["playing"] as? Bool ?? false
        playbackRate = payload["playbackRate"] as? Double ?? 0
        duration = (payload["durationMicros"] as? Double ?? 0) / 1_000_000
        elapsedTime = (payload["elapsedTimeMicros"] as? Double ?? 0) / 1_000_000
        timestamp = (payload["timestampEpochMicros"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1_000_000)
        }
        artworkBase64 = payload["artworkData"] as? String
        shuffleMode = payload["shuffleMode"] as? Int ?? 1
        repeatMode = (payload["repeatMode"] as? Int).flatMap(RepeatMode.init) ?? .off
    }
}

/// Folds `mediaremote-adapter stream` JSON lines (full snapshots or diffs) into current state.
struct NowPlayingStreamParser {
    private var payload: [String: Any] = [:]

    mutating func consume(line: Data) -> NowPlayingState? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let update = object["payload"] as? [String: Any]
        else { return nil }

        if object["diff"] as? Bool == true {
            for (key, value) in update {
                if value is NSNull {
                    payload.removeValue(forKey: key)
                } else {
                    payload[key] = value
                }
            }
        } else {
            payload = update.filter { !($0.value is NSNull) }
        }
        return NowPlayingState(payload: payload)
    }
}
