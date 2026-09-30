import CoreGraphics
import Foundation
import Testing

@testable import MacIsland

struct HomeGridTests {
    private func cell(_ column: Int, _ row: Int) -> GridCell { GridCell(column: column, row: row) }

    private func rect(_ column: Int, _ row: Int, _ columns: Int, _ rows: Int) -> GridRect {
        GridRect(origin: cell(column, row), size: GridSize(columns, rows))
    }

    @Test func theGridIs472WideAndItsSpansAreEightyLessEight() {
        #expect(Theme.Metrics.homeColumnWidth == 72)
        #expect((1...6).map { HomeGridSpec.width(columns: $0) } == [72, 152, 232, 312, 392, 472])
        #expect((1...3).map { HomeGridSpec.height(rows: $0) } == [64, 138, 212])
        #expect(HomeGridSpec.width(columns: 6) == Theme.Metrics.homeContentWidth)
    }

    @Test func theDefaultPacksIntoTwoRows() {
        let packed = HomeGridSpec.pack([GridSize(3, 1), GridSize(3, 1), GridSize(1, 1), GridSize(5, 1)])
        #expect(packed == [rect(0, 0, 3, 1), rect(3, 0, 3, 1), rect(0, 1, 1, 1), rect(1, 1, 5, 1)])
        #expect(HomeGridSpec.rowsUsed(packed) == 2)
    }

    @Test func aTallWidgetSharesRowsWithItsNeighbours() {
        let packed = HomeGridSpec.pack([GridSize(3, 1), GridSize(3, 2), GridSize(1, 1), GridSize(2, 1)])
        #expect(packed[1] == rect(3, 0, 3, 2))
        #expect(packed[2] == rect(0, 1, 1, 1))
        #expect(packed[3] == rect(1, 1, 2, 1))
        #expect(HomeGridSpec.rowsUsed(packed) == 2)
    }

    @Test func aSizeThatOverflowsGetsNilAndALaterOneStillFits() {
        let packed = HomeGridSpec.pack([GridSize(6, 2), GridSize(3, 2), GridSize(1, 1)])
        #expect(packed[0] == rect(0, 0, 6, 2))
        #expect(packed[1] == nil)
        #expect(packed[2] == rect(0, 2, 1, 1))
        #expect(HomeGridSpec.rowsUsed(packed) == 3)
    }

    @Test func unsetAndOversizedSizesAreNeverPlaced() {
        let packed = HomeGridSpec.pack([.unset, GridSize(7, 1), GridSize(1, 4), GridSize(1, 1)])
        #expect(packed == [nil, nil, nil, rect(0, 0, 1, 1)])
        #expect(HomeGridSpec.rowsUsed([nil]) == 0)
    }

    @Test func aFullGridRefusesTheNext() {
        let packed = HomeGridSpec.pack(Array(repeating: GridSize(6, 1), count: 4))
        #expect(packed.compactMap { $0 }.count == 3)
        #expect(packed[3] == nil)
        #expect(HomeGridSpec.freeCells(packed, rows: 3) == 0)
    }

    @Test func framesFollowTheColumnAndRowPitch() {
        #expect(HomeGridSpec.frame(of: rect(3, 0, 3, 1)) == CGRect(x: 240, y: 0, width: 232, height: 64))
        #expect(HomeGridSpec.frame(of: rect(1, 1, 5, 1)) == CGRect(x: 80, y: 74, width: 392, height: 64))
        #expect(HomeGridSpec.frame(of: rect(0, 1, 6, 2)) == CGRect(x: 0, y: 74, width: 472, height: 138))
    }

    @Test func aPointRoundsToTheNearestCellAndClampsToFit() {
        let small = GridSize(1, 1)
        #expect(HomeGridSpec.cell(nearest: CGPoint(x: 39, y: 36), size: small) == cell(0, 0))
        #expect(HomeGridSpec.cell(nearest: CGPoint(x: 41, y: 38), size: small) == cell(1, 1))
        #expect(HomeGridSpec.cell(nearest: CGPoint(x: -50, y: -50), size: small) == cell(0, 0))
        #expect(HomeGridSpec.cell(nearest: CGPoint(x: 900, y: 900), size: small) == cell(5, 2))
        #expect(HomeGridSpec.cell(nearest: CGPoint(x: 900, y: 900), size: GridSize(3, 2)) == cell(3, 1))
    }

    @Test func insertionCountsWhoStartsBefore() {
        // Music lifted from the default: the others pack as Today (0,0), Quick Tools (3,0), Timers (0,1).
        let withoutMusic = HomeGridSpec.pack([GridSize(3, 1), GridSize(1, 1), GridSize(5, 1)])
        #expect(HomeGridSpec.insertionIndex(for: cell(0, 0), among: withoutMusic) == 0)
        #expect(HomeGridSpec.insertionIndex(for: cell(3, 0), among: withoutMusic) == 1)
        // Quick Tools lifted: Today (0,0), Music (3,0), Timers (0,1).
        let withoutTools = HomeGridSpec.pack([GridSize(3, 1), GridSize(3, 1), GridSize(5, 1)])
        #expect(HomeGridSpec.insertionIndex(for: cell(5, 1), among: withoutTools) == 3)
        #expect(HomeGridSpec.insertionIndex(for: cell(0, 0), among: [nil, nil]) == 0)
    }

    @Test func nearestSizePicksByDistanceAndTiesGoSmaller() {
        let sizes = [GridSize(2, 1), GridSize(3, 1), GridSize(6, 1), GridSize(3, 2)]
        #expect(HomeGridSpec.nearest(to: CGSize(width: 240, height: 70), among: sizes) == GridSize(3, 1))
        #expect(HomeGridSpec.nearest(to: CGSize(width: 440, height: 60), among: sizes) == GridSize(6, 1))
        #expect(HomeGridSpec.nearest(to: CGSize(width: 232, height: 140), among: sizes) == GridSize(3, 2))
        // Halfway between 152 and 232 wide: the smaller wins.
        #expect(HomeGridSpec.nearest(to: CGSize(width: 192, height: 64), among: sizes) == GridSize(2, 1))
        #expect(HomeGridSpec.nearest(to: CGSize(width: 192, height: 64), among: []) == .unset)
    }

    @Test func freeCellsCountWhatNothingCovers() {
        let packed = HomeGridSpec.pack([GridSize(3, 1), GridSize(3, 1), GridSize(1, 1), GridSize(5, 1)])
        #expect(HomeGridSpec.freeCells(packed, rows: 2) == 0)
        #expect(HomeGridSpec.freeCells(packed, rows: 3) == 6)
        #expect(HomeGridSpec.freeCells([], rows: 3) == 18)
        #expect(HomeGridSpec.freeCells([rect(0, 0, 3, 1)], rows: 1) == 3)
    }

    @Test func sizesRoundTripAsText() throws {
        let data = try JSONEncoder().encode([GridSize(3, 1), GridSize(6, 2)])
        #expect(String(decoding: data, as: UTF8.self) == #"["3x1","6x2"]"#)
        #expect(try JSONDecoder().decode([GridSize].self, from: data) == [GridSize(3, 1), GridSize(6, 2)])
        let unknown = try JSONDecoder().decode([GridSize].self, from: Data(#"["wide","0x1",4]"#.utf8))
        #expect(unknown == [.unset, .unset, .unset])
        #expect(GridSize(2, 1) < GridSize(3, 1))
        #expect(GridSize(6, 1) < GridSize(3, 3))
    }
}
