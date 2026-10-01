import AppKit
import SwiftUI
import Testing

@testable import MacIsland

/// The Shelf's rows, drawn by AppKit inside a host taller than the Shelf, as the island's panel is. `ImageRenderer` (the snapshots) draws
/// no `ScrollView` content, so it could not see that `containerRelativeFrame` (commit dc0d646) sized the row to the window instead of the
/// space under the header. In the app that put a dropped file below the island's edge: it was on the Shelf but never showed. Here the
/// clipboard card is what shows it (it ran 105 pt past the Shelf); the file stayed in place in this host, so that test only checks it is
/// drawn, and centered.
@MainActor
struct ShelfRowTests {
    private static let width: CGFloat = 472
    /// The header (`SegmentedChoice` is 24 pt) and the 6 pt under it.
    private static let rowTop: CGFloat = 24 + 6
    private static var rowMidY: CGFloat { (rowTop + Theme.Metrics.shelfHeight) / 2 }

    /// Draws the Shelf at the top of a panel-tall host on black, in a window that is never shown, and returns its bitmap.
    private func draw(_ viewModel: IslandViewModel) async throws -> (NSBitmapImageRep, scale: CGFloat) {
        let size = CGSize(width: Self.width, height: Theme.Metrics.panelHeight)
        let hosting = NSHostingView(
            rootView: ShelfView(viewModel: viewModel, dropZone: nil)
                .frame(width: Self.width, height: Theme.Metrics.shelfHeight)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return (rep, CGFloat(rep.pixelsWide) / size.width)
    }

    /// The bounds, in points from the top left, of everything below the header drawn brighter than `threshold`, or nil if nothing is.
    private func rowBounds(_ rep: NSBitmapImageRep, scale: CGFloat, threshold: CGFloat) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in Int(Self.rowTop * scale)..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), color.brightnessComponent > threshold else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            .applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
    }

    @Test func aFileOnTheShelfIsDrawnCenteredUnderTheHeader() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "Shelf".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let viewModel = TestSupport.makeViewModel()
        viewModel.shelf.add([file])

        let (rep, scale) = try await draw(viewModel)
        let item = try #require(rowBounds(rep, scale: scale, threshold: 0.3), "the file isn't drawn")
        #expect(item.maxY <= Theme.Metrics.shelfHeight, "the file is drawn below the Shelf")
        // Loose: the icon has some clear space of its own, so its drawn part isn't exactly centered.
        #expect(abs(item.midY - Self.rowMidY) < 4, "the file isn't centered under the header")
    }

    @Test func aClipboardCardFillsTheSpaceUnderTheHeader() async throws {
        let viewModel = TestSupport.makeViewModel()
        viewModel.clipboard.record(.text("Meeting notes: ship the island"))
        viewModel.setShelfMode(.clipboard)

        let (rep, scale) = try await draw(viewModel)
        // Low enough to take in the card's fill, which is all but black.
        let card = try #require(rowBounds(rep, scale: scale, threshold: 0.03), "the card isn't drawn")
        #expect(abs(card.minY - Self.rowTop) < 1.5)
        #expect(abs(card.maxY - Theme.Metrics.shelfHeight) < 1.5)
    }
}
