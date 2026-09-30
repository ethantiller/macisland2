import AppKit
import Testing

@testable import MacIsland

struct ArtworkAccentTests {
    @Test func darkSaturatedColorIsLiftedToReadOnBlack() throws {
        let navy = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.45, alpha: 1)
        let accent = try #require(ArtworkAccent.legible(navy))
        let contrast = (ArtworkAccent.luminance(of: accent) + 0.05) / 0.05
        #expect(contrast >= 7)
    }

    @Test func alreadyBrightColorIsUnchanged() throws {
        let yellow = NSColor(srgbRed: 1, green: 0.85, blue: 0.1, alpha: 1)
        let accent = try #require(ArtworkAccent.legible(yellow))
        #expect(abs(accent.redComponent - 1) < 0.001)
    }

    @Test func grayArtFallsBackToWhite() {
        #expect(ArtworkAccent.legible(NSColor(srgbRed: 0.4, green: 0.4, blue: 0.42, alpha: 1)) == nil)
    }
}
