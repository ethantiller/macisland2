import Foundation

/// Version 1 of Home's layout was rows of widgets that shared a row's width. Version 2 is one ordered list, each widget
/// with a size on a 6-column grid. This turns the first into the second, once, when a v1 layout is read. Pure, and
/// frozen: it describes the shapes that were stored, so it doesn't follow the catalog as widgets change.
enum HomeLayoutMigration {
    /// A v1 placement, with the widget as the raw string it was stored as, so the retired Timer Chips can still be read.
    struct V1Placement: Decodable, Equatable {
        var id: UUID
        var widget: String
        var options: WidgetOptions

        init(id: UUID = UUID(), widget: String, options: WidgetOptions = WidgetOptions()) {
            self.id = id
            self.widget = widget
            self.options = options
        }

        enum CodingKeys: String, CodingKey { case id, widget, options }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            widget = try container.decode(String.self, forKey: .widget)
            options = try container.decodeIfPresent(WidgetOptions.self, forKey: .options) ?? WidgetOptions()
        }
    }

    /// The widgets that kept their own width in v1 (80 pt); everything else, custom widgets included, shared the rest.
    private static let fixedInV1: Set<String> = ["quickTools", "weather", "battery"]
    /// The widget that became Timers & Shelf.
    private static let retired = "timerChips"

    /// What a custom widget could be in v1: any of the value sizes. `normalized` narrows it to the kind's own sizes.
    private static let customColumns = [1, 2, 3]

    static func migrate(rows: [[V1Placement]], hidden: [V1Placement]) -> HomeLayout {
        var hasClockActions = rows.joined().contains { $0.widget == "clockActions" }
        var widgets: [WidgetPlacement] = []

        for source in rows {
            // Timer Chips is Timers & Shelf now, unless there already is one (it had no options to lose).
            var row: [V1Placement] = []
            for placement in source {
                guard placement.widget == retired else {
                    row.append(placement)
                    continue
                }
                if !hasClockActions {
                    hasClockActions = true
                    row.append(V1Placement(id: placement.id, widget: "clockActions"))
                }
            }
            widgets.append(contentsOf: sized(row))
        }

        let off = hidden.compactMap { placement -> WidgetPlacement? in
            guard let widget = WidgetID(rawValue: placement.widget) else { return nil }
            return WidgetPlacement(
                id: placement.id, widget: widget, size: defaultSize(of: widget), options: placement.options)
        }
        return HomeLayout(widgets: widgets, hidden: off)
    }

    /// One v1 row as sized placements: fixed widgets get a column, and the flexible ones share the other columns as
    /// evenly as they can, earlier ones taking the extra, each at the largest width it has that is no more than its share.
    private static func sized(_ row: [V1Placement]) -> [WidgetPlacement] {
        let known = row.compactMap { placement in WidgetID(rawValue: placement.widget).map { (placement, $0) } }
        let flexibleCount = known.filter { !fixedInV1.contains($0.0.widget) }.count
        let fixedCount = known.count - flexibleCount
        let free = max(Theme.Metrics.homeColumns - fixedCount, flexibleCount)
        var flexibleSeen = 0
        return known.map { placement, widget in
            var share = 1
            if !fixedInV1.contains(placement.widget) {
                share = free / flexibleCount + (flexibleSeen < free % flexibleCount ? 1 : 0)
                flexibleSeen += 1
            }
            return WidgetPlacement(
                id: placement.id, widget: widget, size: GridSize(columns: width(of: widget, atMost: share), rows: 1),
                options: placement.options)
        }
    }

    private static func width(of widget: WidgetID, atMost share: Int) -> Int {
        let columns: [Int]
        if case .builtIn(let builtIn) = widget {
            columns = WidgetCatalog.descriptor(builtIn: builtIn).sizes.filter { $0.rows == 1 }.map(\.columns)
        } else {
            columns = customColumns
        }
        return columns.filter { $0 <= share }.max() ?? columns.min() ?? 1
    }

    private static func defaultSize(of widget: WidgetID) -> GridSize {
        if case .builtIn(let builtIn) = widget { return WidgetCatalog.descriptor(builtIn: builtIn).defaultSize }
        return GridSize(2, 1)
    }
}
