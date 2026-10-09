import AudioToolbox
import Foundation
import Testing

@testable import MacIsland

/// What the QA audit found: hostile or damaged input must not hang, crash, or erase anything.
@MainActor
struct QAFixTests {
    @Test func aHugeInviteIsSearchedInLinearTime() {
        let junk = String(repeating: "https://x.example/a?b=c&d=e,", count: 3_000)
        let start = Date()
        let none = MeetingLink.find(in: [junk])
        #expect(none == nil)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(MeetingLink.find(in: [junk + " join HTTPS://Meet.Google.com/abc-defg-hij."])?.host?.lowercased() == "meet.google.com")
    }

    @Test func aNotesFileThatWillNotLoadIsKeptNotErased() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("notes.json")
        try Data(#"{"notes":[{"body":"Keep me"}]}"#.utf8).write(to: file)
        let model = NotesModel(directory: directory)
        model.save()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("notes.unreadable-") })
        #expect(model.notes.isEmpty)
    }

    @Test func conversionsNeverTrap() {
        #expect(safeInt(Double.nan) == 0)
        #expect(safeInt(Double.infinity) > 0)
        #expect(safeInt(-1e300) < 0)
        #expect(formatTime(1e300).contains(":"))
        #expect(formatTime(.nan) == "0:00")
        #expect(LyricsModel.key(for: { var s = NowPlayingState(); s.duration = 1e306; return s }()).isEmpty == false)
    }

    @Test func tokenCountsAreSane() {
        #expect(AgentTokens.count(NSNumber(value: -5)) == 0)
        #expect(AgentTokens.count(NSNumber(value: Int.max)) == 1_000_000_000_000)
        #expect(AgentTokens.count("x") == 0)
    }

    @Test func aDamagedCacheHoursArrayIsMadeWhole() throws {
        let json = #"{"version":2,"hours":{"1|claudeCode":[1,2]}}"#
        let data = try JSONDecoder().decode(AgentUsageData.self, from: Data(json.utf8))
        #expect(data.hours["1|claudeCode"]?.count == 24)
    }

    @Test func aCRLFLogSplitsIntoLines() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("{\"a\":1}\r\n{\"b\":2}\r\n".utf8).write(to: file)
        let tail = AgentLogTail.read(file, from: 0)
        #expect(tail?.lines == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test func theTapPlaysTheAppNotTheHeadsetMicrophone() {
        let state = TapState(level: 1, sampleRate: 48_000)
        let frames = 64
        var mic = [Float](repeating: 0.3, count: frames)
        var tap = [Float](repeating: 0.7, count: frames * 2)
        var out = [Float](repeating: 0, count: frames * 2)
        mic.withUnsafeMutableBytes { micBytes in
            tap.withUnsafeMutableBytes { tapBytes in
                out.withUnsafeMutableBytes { outBytes in
                    let input = AudioBufferList.allocate(maximumBuffers: 2)
                    input[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(micBytes.count), mData: micBytes.baseAddress)
                    input[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(tapBytes.count), mData: tapBytes.baseAddress)
                    let output = AudioBufferList.allocate(maximumBuffers: 1)
                    output[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(outBytes.count), mData: outBytes.baseAddress)
                    state.process(input.unsafeMutablePointer, output.unsafeMutablePointer)
                    free(input.unsafeMutablePointer)
                    free(output.unsafeMutablePointer)
                }
            }
        }
        #expect(out.allSatisfy { abs($0 - 0.7) < 0.0001 })
        #expect(state.heard)
    }
}
