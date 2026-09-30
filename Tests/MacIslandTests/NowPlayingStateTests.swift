import Foundation
import Testing
@testable import MacIsland

struct NowPlayingStreamParserTests {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    @Test func fullSnapshotReplacesState() throws {
        var parser = NowPlayingStreamParser()
        let result = parser.consume(line: line("""
        {"type":"data","diff":false,"payload":{"title":"Song","artist":"Band","album":"LP",
        "playing":true,"playbackRate":1,"durationMicros":180000000,"elapsedTimeMicros":30000000,
        "timestampEpochMicros":1700000000000000,"bundleIdentifier":"com.spotify.client"}}
        """))
        let state = try #require(result)

        #expect(state.title == "Song")
        #expect(state.artist == "Band")
        #expect(state.isPlaying)
        #expect(state.duration == 180)
        #expect(state.elapsedTime == 30)
        #expect(state.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(state.bundleIdentifier == "com.spotify.client")
    }

    @Test func diffMergesAndNullRemovesKeys() throws {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: line("""
        {"type":"data","diff":false,"payload":{"title":"Song","artist":"Band","playing":true}}
        """))
        let result = parser.consume(line: line("""
        {"type":"data","diff":true,"payload":{"playing":false,"artist":null}}
        """))
        let state = try #require(result)

        #expect(state.title == "Song")
        #expect(state.artist == "")
        #expect(!state.isPlaying)
    }

    @Test func emptyPayloadMeansNothingPlaying() throws {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: line(#"{"type":"data","diff":false,"payload":{"title":"Song"}}"#))
        let result = parser.consume(line: line(#"{"type":"data","diff":false,"payload":{}}"#))
        let state = try #require(result)
        #expect(!state.hasMedia)
    }

    @Test func ignoresGarbage() {
        var parser = NowPlayingStreamParser()
        let notJSON = parser.consume(line: line("not json"))
        let wrongType = parser.consume(line: line(#"{"type":"other"}"#))
        #expect(notJSON == nil)
        #expect(wrongType == nil)
    }
}

struct NowPlayingElapsedTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func state(playing: Bool, rate: Double = 1) -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "Song"
        state.isPlaying = playing
        state.playbackRate = rate
        state.duration = 100
        state.elapsedTime = 10
        state.timestamp = start
        return state
    }

    @Test func advancesWhilePlaying() {
        #expect(state(playing: true).elapsed(at: start.addingTimeInterval(5)) == 15)
    }

    @Test func respectsPlaybackRate() {
        #expect(state(playing: true, rate: 2).elapsed(at: start.addingTimeInterval(5)) == 20)
    }

    @Test func frozenWhilePaused() {
        #expect(state(playing: false).elapsed(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func clampsToDuration() {
        #expect(state(playing: true).elapsed(at: start.addingTimeInterval(500)) == 100)
    }
}
