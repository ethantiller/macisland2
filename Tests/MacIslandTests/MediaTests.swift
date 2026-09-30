import Foundation
import Testing

@testable import MacIsland

struct LRCTests {
    private let source = """
        [ar:Someone]
        [00:12.50] First line
        [00:20.00] Second line
        [00:30.00]
        [00:35.00][01:05.25] Chorus
        """

    @Test func parsesTimedLinesInOrderAndSkipsTags() {
        let lines = LRC.parse(source)
        #expect(lines.map(\.text) == ["First line", "Second line", "", "Chorus", "Chorus"])
        #expect(lines.first?.time == 12.5)
        #expect(lines.last?.time == 65.25)
    }

    @Test func findsTheLineBeingSung() {
        let lines = LRC.parse(source)
        #expect(LRC.text(at: 5, in: lines) == nil)
        #expect(LRC.text(at: 12.5, in: lines) == "First line")
        #expect(LRC.text(at: 25, in: lines) == "Second line")
        // An empty line is an instrumental gap.
        #expect(LRC.text(at: 32, in: lines) == nil)
        #expect(LRC.text(at: 999, in: lines) == "Chorus")
    }
}

@MainActor
struct LyricsModelTests {
    private func track(_ title: String = "Song", duration: TimeInterval = 200) -> NowPlayingState {
        var state = NowPlayingState()
        state.title = title
        state.artist = "Artist Name"
        state.album = "Album"
        state.duration = duration
        return state
    }

    private let response = Data(#"{"syncedLyrics": "[00:01.00] Hello\n[00:05.00] World"}"#.utf8)

    @Test func buildsTheLookupFromTheTrack() {
        let url = LyricsModel.url(for: track())?.absoluteString
        #expect(url?.hasPrefix("https://lrclib.net/api/get?") == true)
        #expect(url?.contains("track_name=Song") == true)
        #expect(url?.contains("artist_name=Artist%20Name") == true)
        #expect(url?.contains("album_name=Album") == true)
        #expect(url?.contains("duration=200") == true)
        var untitled = track()
        untitled.artist = ""
        #expect(LyricsModel.url(for: untitled) == nil)
    }

    @Test func plainOrMissingLyricsAreEmpty() {
        #expect(LyricsModel.lines(fromResponse: Data(#"{"plainLyrics": "x", "syncedLyrics": null}"#.utf8)).isEmpty)
        #expect(LyricsModel.lines(fromResponse: Data("nope".utf8)).isEmpty)
        // Stamps without words (an instrumental) leave no lyrics, so no blank row.
        #expect(LyricsModel.lines(fromResponse: Data(#"{"syncedLyrics": "[00:00.00] \n[00:30.00]"}"#.utf8)).isEmpty)
        #expect(LyricsModel.lines(fromResponse: response).count == 2)
    }

    @Test func doesNothingWhileOff() async throws {
        let lyrics = LyricsModel()
        var requests = 0
        lyrics.fetch = { _ in
            requests += 1; return nil
        }
        lyrics.track(track())
        try await Task.sleep(for: .milliseconds(50))
        #expect(requests == 0 && lyrics.lines.isEmpty)
    }

    @Test func fetchesOncePerTrackAndCaches() async throws {
        let lyrics = LyricsModel()
        var requests = 0
        let body = response
        lyrics.fetch = { _ in
            requests += 1; return body
        }
        lyrics.setEnabled(true, for: NowPlayingState())
        lyrics.track(track())
        try await Task.sleep(for: .milliseconds(100))
        #expect(lyrics.lines.count == 2)

        // Progress updates for the same track don't ask again.
        var later = track()
        later.elapsedTime = 30
        lyrics.track(later)
        // Another track, then back: the first comes from the cache.
        lyrics.track(track("Other"))
        try await Task.sleep(for: .milliseconds(100))
        lyrics.track(track())
        #expect(lyrics.lines.count == 2)
        #expect(requests == 2)
    }

    @Test func aFailedLookupLeavesNoLyrics() async throws {
        let lyrics = LyricsModel()
        lyrics.fetch = { _ in nil }
        lyrics.setEnabled(true, for: NowPlayingState())
        lyrics.track(track())
        try await Task.sleep(for: .milliseconds(100))
        #expect(lyrics.lines.isEmpty)
    }
}

@MainActor
struct PlayerControlsTests {
    @Test func shuffleAndRepeatToggleOptimistically() {
        let model = NowPlayingModel(adapter: nil)
        #expect(!model.state.isShuffling)
        model.toggleShuffle()
        #expect(model.state.isShuffling)
        model.toggleShuffle()
        #expect(!model.state.isShuffling)

        model.cycleRepeat()
        #expect(model.state.repeatMode == .playlist)
        model.cycleRepeat()
        #expect(model.state.repeatMode == .track)
        model.cycleRepeat()
        #expect(model.state.repeatMode == .off)
    }

    @Test func streamCarriesShuffleAndRepeat() {
        var parser = NowPlayingStreamParser()
        let line = #"{"type":"data","diff":false,"payload":{"title":"T","shuffleMode":3,"repeatMode":2}}"#
        let state = parser.consume(line: Data(line.utf8))
        #expect(state?.isShuffling == true)
        #expect(state?.repeatMode == .track)
    }

    @Test func onlyMusicAndSpotifyAreScriptable() {
        #expect(ScriptablePlayer(bundleIdentifier: "com.apple.Music") == .music)
        #expect(ScriptablePlayer(bundleIdentifier: "com.spotify.client") == .spotify)
        #expect(ScriptablePlayer(bundleIdentifier: "com.google.Chrome") == nil)
        #expect(ScriptablePlayer.music.supportsFavorite)
        #expect(!ScriptablePlayer.spotify.supportsFavorite)
    }

    @Test func scriptsOnlyTalkToARunningPlayer() {
        let script = ScriptablePlayer.spotify.setVolumeScript(150)
        #expect(script.hasPrefix(#"if application "Spotify" is running then"#))
        #expect(script.hasSuffix("set sound volume to 100"))
        #expect(ScriptablePlayer.music.setFavoriteScript(true).hasSuffix("set favorited of current track to true"))
    }

    @Test func bothPlayerHeightsGrowAndShrinkWithTheLyricRow() async throws {
        let viewModel = TestSupport.makeViewModel()
        let lyrics = viewModel.nowPlaying.lyrics
        var body: Data? = Data(#"{"syncedLyrics": "[00:10.00] Hi"}"#.utf8)
        lyrics.fetch = { _ in body }
        lyrics.setEnabled(true, for: NowPlayingState())
        var state = NowPlayingState()
        state.title = "T"
        state.artist = "A"
        viewModel.nowPlaying.apply(state)

        // A lookup in flight has no row yet.
        let bare = (peek: viewModel.mediaContentHeight(peek: true), tab: viewModel.mediaContentHeight(peek: false))
        #expect(lyrics.lines.isEmpty)
        try await Task.sleep(for: .milliseconds(100))

        // Lines that have not started (the first is at 10 s, the track is at 0) still have their row.
        #expect(!lyrics.lines.isEmpty)
        #expect(viewModel.mediaContentHeight(peek: true) == bare.peek + Theme.Metrics.lyricsRowHeight)
        #expect(viewModel.mediaContentHeight(peek: false) == bare.tab + Theme.Metrics.lyricsRowHeight)

        // The next track has none: the row goes at once and stays gone.
        body = nil
        state.title = "Other"
        viewModel.nowPlaying.apply(state)
        #expect(viewModel.mediaContentHeight(peek: true) == bare.peek)
        #expect(viewModel.mediaContentHeight(peek: false) == bare.tab)
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.mediaContentHeight(peek: true) == bare.peek)
        #expect(viewModel.mediaContentHeight(peek: false) == bare.tab)
    }

    @Test func lyricsRowOnlyTakesHeightWhenThereAreLyrics() async throws {
        let viewModel = TestSupport.makeViewModel()
        let base = viewModel.contentHeight(for: .media)
        #expect(base == Theme.Metrics.glanceHeight)
        let lyrics = viewModel.nowPlaying.lyrics
        lyrics.fetch = { _ in Data(#"{"syncedLyrics": "[00:01.00] Hi"}"#.utf8) }
        lyrics.setEnabled(true, for: NowPlayingState())
        var state = NowPlayingState()
        state.title = "T"
        state.artist = "A"
        viewModel.nowPlaying.apply(state)
        try await Task.sleep(for: .milliseconds(100))
        // Music is playing now, so the player is its full height, with the lyric line.
        #expect(viewModel.contentHeight(for: .media) == viewModel.mediaContentHeight(peek: false))
        #expect(viewModel.contentHeight(for: .media) > base + Theme.Metrics.lyricsRowHeight)
        #expect(
            viewModel.mediaContentHeight(peek: false) - viewModel.mediaContentHeight(peek: true)
                == Theme.Metrics.playerArtwork - Theme.Metrics.playerPeekArtwork + Theme.Metrics.playerTopInset)
    }
}
