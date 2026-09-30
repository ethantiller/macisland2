import CoreGraphics

/// A widget's size on Home's grid, in columns by rows. Stored as "3x1"; anything unreadable decodes to `.unset`.
struct GridSize: Hashable, Codable, Comparable, CustomStringConvertible {
    var columns: Int
    var rows: Int

    static let unset = GridSize(columns: 0, rows: 0)

    var isUnset: Bool { columns <= 0 || rows <= 0 }
    var cellCount: Int { max(columns, 0) * max(rows, 0) }
    var description: String { "\(columns)x\(rows)" }
    /// "3 × 1", for the editor.
    var displayName: String { "\(columns) \u{00D7} \(rows)" }

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    init(_ columns: Int, _ rows: Int) {
        self.init(columns: columns, rows: rows)
    }

    init(string: String) {
        let parts = string.split(separator: "x")
        guard parts.count == 2, let columns = Int(parts[0]), let rows = Int(parts[1]), columns > 0, rows > 0 else {
            self = .unset
            return
        }
        self.init(columns: columns, rows: rows)
    }

    init(from decoder: Decoder) throws {
        let value = try? decoder.singleValueContainer().decode(String.self)
        self.init(string: value ?? "")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Smallest first: by area, then by width.
    static func < (lhs: GridSize, rhs: GridSize) -> Bool {
        (lhs.cellCount, lhs.columns) < (rhs.cellCount, rhs.columns)
    }
}

/// One cell of the grid. Reading order is row, then column.
struct GridCell: Hashable, Comparable {
    var column: Int
    var row: Int

    static func < (lhs: GridCell, rhs: GridCell) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

/// A widget's place on the grid: its top-left cell and its size.
struct GridRect: Hashable {
    var origin: GridCell
    var size: GridSize

    var endRow: Int { origin.row + size.rows }
}

/// Home's grid as pure math: packing, geometry, and the targets a drag lands on. The renderer and the editor
/// share this, so what the editor shows is what the island draws. Positions are computed, never stored.
enum HomeGridSpec {
    private static var columns: Int { Theme.Metrics.homeColumns }
    private static var columnPitch: CGFloat { Theme.Metrics.homeColumnWidth + Theme.Metrics.rowSpacing }
    private static var rowPitch: CGFloat { Theme.Metrics.homeRowHeight + Theme.Metrics.homeRowGap }

    /// Sparse auto-flow, like CSS grid: each size goes at the first free spot at or after the previous one in
    /// reading order. A size that can't fit within `maxRows` gets `nil` and the cursor stays, so a later, smaller
    /// one can still be placed.
    static func pack(_ sizes: [GridSize], maxRows: Int = Theme.Metrics.homeMaxRows) -> [GridRect?] {
        var occupied = Set<GridCell>()
        var cursor = 0
        return sizes.map { size in
            guard !size.isUnset, size.columns <= columns, size.rows <= maxRows else { return nil }
            for index in cursor..<(columns * maxRows) {
                let origin = GridCell(column: index % columns, row: index / columns)
                guard origin.column + size.columns <= columns, origin.row + size.rows <= maxRows else { continue }
                let cells = cells(of: GridRect(origin: origin, size: size))
                guard occupied.isDisjoint(with: cells) else { continue }
                occupied.formUnion(cells)
                cursor = index + size.columns
                return GridRect(origin: origin, size: size)
            }
            return nil
        }
    }

    /// How many rows the placed rectangles reach down to.
    static func rowsUsed(_ rects: [GridRect?]) -> Int {
        rects.compactMap { $0?.endRow }.max() ?? 0
    }

    /// 80 n - 8.
    static func width(columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        return CGFloat(columns) * Theme.Metrics.homeColumnWidth + CGFloat(columns - 1) * Theme.Metrics.rowSpacing
    }

    /// 74 m - 10.
    static func height(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * Theme.Metrics.homeRowHeight + CGFloat(rows - 1) * Theme.Metrics.homeRowGap
    }

    /// Where a rectangle sits in grid space, measured from the grid's top left.
    static func frame(of rect: GridRect) -> CGRect {
        CGRect(
            x: CGFloat(rect.origin.column) * columnPitch,
            y: CGFloat(rect.origin.row) * rowPitch,
            width: width(columns: rect.size.columns),
            height: height(rows: rect.size.rows))
    }

    /// The cell whose top left is nearest a point (a widget's top left in grid space), clamped so it fits.
    static func cell(nearest topLeft: CGPoint, size: GridSize, maxRows: Int = Theme.Metrics.homeMaxRows) -> GridCell {
        let column = Int((topLeft.x / columnPitch).rounded())
        let row = Int((topLeft.y / rowPitch).rounded())
        return GridCell(
            column: min(max(column, 0), max(columns - size.columns, 0)),
            row: min(max(row, 0), max(maxRows - size.rows, 0)))
    }

    /// Where in the list a widget dropped at `cell` goes: how many of the other widgets start before it.
    static func insertionIndex(for cell: GridCell, among others: [GridRect?]) -> Int {
        others.compactMap { $0 }.filter { $0.origin < cell }.count
    }

    /// The size nearest an extent in points, so a resize handle snaps. A tie goes to the smaller size.
    static func nearest(to extent: CGSize, among sizes: [GridSize]) -> GridSize {
        func distance(_ size: GridSize) -> CGFloat {
            let dx = width(columns: size.columns) - extent.width
            let dy = height(rows: size.rows) - extent.height
            return dx * dx + dy * dy
        }
        return sizes.min { lhs, rhs in
            let (a, b) = (distance(lhs), distance(rhs))
            return a == b ? lhs < rhs : a < b
        } ?? .unset
    }

    /// Cells in the first `rows` rows that nothing covers.
    static func freeCells(_ rects: [GridRect?], rows: Int) -> Int {
        let covered = Set(rects.compactMap { $0 }.flatMap(cells(of:))).filter { $0.row < rows && $0.column < columns }
        return max(rows * columns - covered.count, 0)
    }

    /// The cells in the first `rows` rows that nothing covers, in reading order.
    static func emptyCells(_ rects: [GridRect?], rows: Int) -> [GridCell] {
        let covered = Set(rects.compactMap { $0 }.flatMap(cells(of:)))
        return (0..<max(rows, 0)).flatMap { row in
            (0..<columns).map { GridCell(column: $0, row: row) }
        }.filter { !covered.contains($0) }
    }

    private static func cells(of rect: GridRect) -> [GridCell] {
        (rect.origin.row..<rect.endRow).flatMap { row in
            (rect.origin.column..<(rect.origin.column + rect.size.columns)).map { GridCell(column: $0, row: row) }
        }
    }
}
