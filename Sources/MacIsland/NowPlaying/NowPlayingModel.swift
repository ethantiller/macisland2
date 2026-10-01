import AppKit
import SwiftUI

@MainActor
@Observable
final class NowPlayingModel {
    private(set) var state = NowPlayingState()
    private(set) var artwork: NSImage?
    /// The live tint for music: the artwork's most vivid color, or white for gray art.
    private(set) var accent: Color = Theme.Tint.neutral
    let lyrics: LyricsModel
    /// Apple Music's Favorite for the current track, once asked. `nil` when unknown or unsupported.
    private(set) var isFavorite: Bool?
    /// The player's own volume from 0 to 1, once asked. `nil` when unknown or unsupported.
    private(set) var appVolume: Double?

    @ObservationIgnored private let adapter: MediaRemoteAdapter?
    /// How a transport command reaches Music or Spotify. Replaced in tests, so they never touch a real player.
    @ObservationIgnored var sendToPlayer: (PlayerCommand, ScriptablePlayer) async -> Bool = {
        await PlayerScripting.send($0, to: $1)
    }
    @ObservationIgnored var seekPlayer: (TimeInterval, ScriptablePlayer) async -> Bool = {
        await PlayerScripting.seek(to: $0, on: $1)
    }

    convenience init() {
        self.init(adapter: MediaRemoteAdapter())
    }

    init(adapter: MediaRemoteAdapter?, lyrics: LyricsModel? = nil) {
        self.adapter = adapter
        self.lyrics = lyrics ?? LyricsModel()
        adapter?.onState = { [weak self] in self?.apply($0) }
    }

    /// Starts reading what is playing. Nothing runs until this: with Music off, the adapter is never started.
    func start() {
        adapter?.start()
    }

    /// Stops the adapter, and forgets what was playing.
    func stop() {
        adapter?.stop()
    }

    func togglePlayPause() {
        send(.playPause) { [adapter] in adapter?.send(.togglePlayPause) }
        // Optimistic update; the stream confirms a moment later.
        let now = Date()
        state.elapsedTime = state.elapsed(at: now)
        state.timestamp = now
        state.isPlaying.toggle()
    }

    func nextTrack() {
        send(.next) { [adapter] in adapter?.send(.nextTrack) }
    }

    func previousTrack() {
        send(.previous) { [adapter] in adapter?.send(.previousTrack) }
    }

    /// Music and Spotify are told directly. macOS's own play and pause goes to whichever app it thinks is
    /// playing, which is a video in a browser tab the moment one starts, however the island is showing the music.
    /// Anything else, and a script that fails, falls back to the system's command.
    private func send(_ command: PlayerCommand, fallback: @escaping @MainActor () -> Void) {
        guard let player else { return fallback() }
        let send = sendToPlayer
        Task { @MainActor in
            if await !send(command, player) { fallback() }
        }
    }

    func toggleShuffle() {
        let mode = state.isShuffling ? 1 : 3
        adapter?.setShuffle(mode)
        state.shuffleMode = mode
    }

    func cycleRepeat() {
        let mode = state.repeatMode.next
        adapter?.setRepeat(mode)
        state.repeatMode = mode
    }

    // MARK: The player itself

    var player: ScriptablePlayer? { ScriptablePlayer(bundleIdentifier: state.bundleIdentifier) }

    /// Asks the player for its Favorite and volume. Called while the Media view is visible.
    func refreshPlayerState() async {
        guard let player else {
            isFavorite = nil
            appVolume = nil
            return
        }
        let volume = await PlayerScripting.volume(of: player)
        appVolume = volume.map { Double($0) / 100 }
        isFavorite = player.supportsFavorite ? await PlayerScripting.isFavorite(on: player) : nil
    }

    func toggleFavorite() {
        guard let player, player.supportsFavorite, let current = isFavorite else { return }
        isFavorite = !current
        PlayerScripting.setFavorite(!current, on: player)
    }

    /// Follows the slider while it is dragged; the player hears it on release.
    func previewAppVolume(_ fraction: Double) {
        appVolume = fraction
    }

    func setAppVolume(_ fraction: Double) {
        guard let player else { return }
        appVolume = fraction
        PlayerScripting.setVolume(Int((fraction * 100).rounded()), of: player)
    }

    func seek(to seconds: TimeInterval) {
        if let player {
            let seek = seekPlayer
            Task { @MainActor [adapter] in
                if await !seek(seconds, player) { adapter?.seek(to: seconds) }
            }
        } else {
            adapter?.seek(to: seconds)
        }
        state.elapsedTime = seconds
        state.timestamp = Date()
    }

    func apply(_ newState: NowPlayingState) {
        if Self.trackChanged(from: state, to: newState) {
            isFavorite = nil
        }
        if newState.artworkBase64 != state.artworkBase64 {
            artwork = newState.artworkBase64
                .flatMap { Data(base64Encoded: $0) }
                .flatMap(NSImage.init(data:))
            accent =
                artwork
                .flatMap(ArtworkAccent.color(from:))
                .map { Color(nsColor: $0) } ?? Theme.Tint.neutral
        }
        if newState.hasMedia != state.hasMedia {
            withAnimation(Theme.Motion.open) { state = newState }
        } else {
            state = newState
        }
        lyrics.track(newState)
    }

    private static func trackChanged(from old: NowPlayingState, to new: NowPlayingState) -> Bool {
        LyricsModel.key(for: old) != LyricsModel.key(for: new) || old.bundleIdentifier != new.bundleIdentifier
    }
}
