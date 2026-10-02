import CoreGraphics
import Foundation

/// Per-widget choices. Flat and optional, so an older file still reads, and every default reproduces today's Home.
struct WidgetOptions: Codable, Equatable {
    /// Quick Tools: nil follows the Tools row (its first four pinned tools).
    var tools: [ToolID]?
    /// Timers & Shelf: the two quick timer lengths. Nil is 5 and 25.
    var timerMinutes: [Int]?
    /// Timers & Shelf: nil is shown.
    var showsPomodoro: Bool?
    var showsShelf: Bool?
    /// Note: nil is the latest note.
    var noteID: UUID?
}

/// One widget placed in a layout, at one of the sizes it has a layout for.
struct WidgetPlacement: Codable, Equatable, Identifiable {
    var id = UUID()
    var widget: WidgetID
    /// `.unset` when a stored placement has none; `HomeLayout.normalized` repairs it.
    var size: GridSize = .unset
    var options = WidgetOptions()

    enum CodingKeys: String, CodingKey { case id, widget, size, options }

    init(id: UUID = UUID(), widget: WidgetID, size: GridSize = .unset, options: WidgetOptions = WidgetOptions()) {
        self.id = id
        self.widget = widget
        self.size = size
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        widget = try container.decode(WidgetID.self, forKey: .widget)
        size = try container.decodeIfPresent(GridSize.self, forKey: .size) ?? .unset
        options = try container.decodeIfPresent(WidgetOptions.self, forKey: .options) ?? WidgetOptions()
    }
}

/// Reads placements one at a time, so a widget this build doesn't know is dropped instead of failing the layout.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

extension HomeLayout {
    /// What is written: `rows` is only ever read (version 1, migrated).
    enum CodingKeys: String, CodingKey { case version, widgets, hidden }
    private enum ReadingKeys: String, CodingKey { case version, rows, widgets, hidden }

    /// Picks by key: `widgets` is version 2, and `rows` is version 1, which is migrated.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ReadingKeys.self)
        if container.contains(.widgets) {
            self.init(
                version: Self.currentVersion,
                widgets: try container.decode([Lossy<WidgetPlacement>].self, forKey: .widgets).compactMap(\.value),
                hidden: (try container.decodeIfPresent([Lossy<WidgetPlacement>].self, forKey: .hidden) ?? [])
                    .compactMap(\.value))
        } else {
            let rows = try container.decode([[Lossy<HomeLayoutMigration.V1Placement>]].self, forKey: .rows)
            let hidden =
                try container.decodeIfPresent([Lossy<HomeLayoutMigration.V1Placement>].self, forKey: .hidden) ?? []
            self = HomeLayoutMigration.migrate(
                rows: rows.map { $0.compactMap(\.value) }, hidden: hidden.compactMap(\.value))
        }
    }
}

struct HomePreset: Identifiable {
    let name: String
    let layout: HomeLayout

    var id: String { name }
}

/// What Home shows: widgets in reading order, each at one of its sizes, packed onto a 6 by 3 grid; and the ones that
/// are off Home. Positions are computed (`HomeGridSpec.pack`), never stored. Pure and `Codable`, so it is tested
/// like `AppSettings.normalized`.
struct HomeLayout: Codable, Equatable {
    static let currentVersion = 2

    var version = HomeLayout.currentVersion
    var widgets: [WidgetPlacement]
    /// Widgets that are off Home, each keeping its options and last size. Anything that didn't fit lands here, and
    /// nothing is ever deleted.
    var hidden: [WidgetPlacement] = []

    /// Looks up a widget's descriptor, or nil when this build doesn't have it (an unknown or removed widget).
    typealias Catalog = (WidgetID) -> WidgetDescriptor?

    // MARK: Presets

    private static func placement(_ widget: BuiltInWidget, _ columns: Int, _ rows: Int = 1) -> WidgetPlacement {
        WidgetPlacement(widget: .builtIn(widget), size: GridSize(columns, rows))
    }

    /// Exactly today's Home: the date and music, then the quick tools beside the timers and the Shelf.
    static let `default` = HomeLayout(widgets: [
        placement(.today, 3), placement(.music, 3), placement(.quickTools, 1), placement(.clockActions, 5),
    ])

    /// Everyday with the System widget in place of the date, for the Settings preview of a feature whose card the person may not have.
    static let showingSystem = HomeLayout(widgets: [
        placement(.system, 3), placement(.music, 3), placement(.quickTools, 1), placement(.clockActions, 5),
    ])

    static let presets: [HomePreset] = [
        HomePreset(name: "Everyday", layout: .default),
        HomePreset(
            name: "Focus",
            layout: HomeLayout(widgets: [
                placement(.today, 3), placement(.reminders, 3), placement(.quickTools, 1), placement(.clockActions, 5),
            ])),
        HomePreset(
            name: "Listening",
            layout: HomeLayout(widgets: [
                placement(.music, 6, 2), placement(.quickTools, 1), placement(.clockActions, 5),
            ])),
        HomePreset(name: "Minimal", layout: HomeLayout(widgets: [placement(.today, 3), placement(.music, 3)])),
        HomePreset(
            name: "Dashboard",
            layout: HomeLayout(widgets: [
                placement(.music, 3, 2), placement(.weather, 3), placement(.today, 3), placement(.quickTools, 1),
                placement(.clockActions, 5),
            ])),
    ]

    // MARK: Geometry

    /// The size a placement is drawn at: its own when this widget has a layout for it, otherwise the nearest that it has.
    func size(of placement: WidgetPlacement, catalog: Catalog) -> GridSize {
        catalog(placement.widget).map { Self.repairedSize(placement.size, for: $0) } ?? placement.size
    }

    /// The widgets' places, in list order: `nil` for one that doesn't fit.
    func rects(catalog: Catalog = WidgetCatalog.descriptor(for:)) -> [GridRect?] {
        HomeGridSpec.pack(widgets.map { size(of: $0, catalog: catalog) })
    }

    /// Where each widget sits on the grid.
    func frames(catalog: Catalog = WidgetCatalog.descriptor(for:)) -> [UUID: GridRect] {
        var frames: [UUID: GridRect] = [:]
        for (placement, rect) in zip(widgets, rects(catalog: catalog)) {
            if let rect { frames[placement.id] = rect }
        }
        return frames
    }

    func rowsUsed(catalog: Catalog = WidgetCatalog.descriptor(for:)) -> Int {
        HomeGridSpec.rowsUsed(rects(catalog: catalog))
    }

    /// Home's height with nothing else open: as tall as its rows. Computed, not measured, like every module.
    func contentHeight(catalog: Catalog = WidgetCatalog.descriptor(for:)) -> CGFloat {
        HomeGridSpec.height(rows: rowsUsed(catalog: catalog))
    }

    /// Nothing is left off the grid and every size is one the widget has.
    func isValid(catalog: Catalog = WidgetCatalog.descriptor(for:)) -> Bool {
        guard !widgets.isEmpty else { return false }
        for placement in widgets {
            guard let descriptor = catalog(placement.widget), descriptor.sizes.contains(placement.size) else {
                return false
            }
        }
        return rects(catalog: catalog).allSatisfy { $0 != nil }
    }

    /// What room is left: whole rows, and the free cells in the rows in use.
    func capacity(catalog: Catalog = WidgetCatalog.descriptor(for:)) -> (rowsLeft: Int, freeCells: Int) {
        let rects = rects(catalog: catalog)
        let used = HomeGridSpec.rowsUsed(rects)
        return (Theme.Metrics.homeMaxRows - used, HomeGridSpec.freeCells(rects, rows: used))
    }

    /// The hint under the preview: "Room for 1 more row", "3 spaces left", or "Home is full".
    func capacityText(catalog: Catalog = WidgetCatalog.descriptor(for:)) -> String {
        let (rowsLeft, freeCells) = capacity(catalog: catalog)
        if rowsLeft > 0 { return "Room for \(rowsLeft) more row\(rowsLeft == 1 ? "" : "s")" }
        if freeCells > 0 { return "\(freeCells) space\(freeCells == 1 ? "" : "s") left" }
        return "Home is full"
    }

    // MARK: Repair

    /// A size the widget has: the one given, else the nearest (the same width first, then the same height), else
    /// its default.
    static func repairedSize(_ size: GridSize, for descriptor: WidgetDescriptor) -> GridSize {
        if descriptor.sizes.contains(size) { return size }
        if !size.isUnset {
            let sameWidth = descriptor.sizes.filter { $0.columns == size.columns }
            if let nearest = sameWidth.min(by: { abs($0.rows - size.rows) < abs($1.rows - size.rows) }) {
                return nearest
            }
            let sameHeight = descriptor.sizes.filter { $0.rows == size.rows }
            if let nearest = sameHeight.min(by: { abs($0.columns - size.columns) < abs($1.columns - size.columns) }) {
                return nearest
            }
        }
        return descriptor.defaultSize
    }

    /// Runs on load, import, and every edit. Repairs, and never deletes: a widget this build has no descriptor for, a
    /// repeat, and one that doesn't fit within the rows goes to `hidden`; a missing or unsupported size becomes the
    /// nearest supported one. Never returns an empty layout.
    static func normalized(_ layout: HomeLayout, catalog: Catalog = WidgetCatalog.descriptor(for:)) -> HomeLayout {
        var placed: [WidgetPlacement] = []
        var sizes: [GridSize] = []
        var hidden: [WidgetPlacement] = []

        func repaired(_ placement: WidgetPlacement) -> WidgetPlacement {
            guard let descriptor = catalog(placement.widget) else { return placement }
            var placement = placement
            placement.size = repairedSize(placement.size, for: descriptor)
            return placement
        }

        func hide(_ placement: WidgetPlacement) {
            if !hidden.contains(where: { $0.widget == placement.widget }) { hidden.append(placement) }
        }

        for source in layout.widgets {
            guard catalog(source.widget) != nil, !placed.contains(where: { $0.widget == source.widget }) else {
                hide(source)
                continue
            }
            let placement = repaired(source)
            if HomeGridSpec.pack(sizes + [placement.size]).last.flatMap({ $0 }) != nil {
                placed.append(placement)
                sizes.append(placement.size)
            } else {
                hide(placement)
            }
        }

        for source in layout.hidden where !placed.contains(where: { $0.widget == source.widget }) {
            hide(repaired(source))
        }

        guard !placed.isEmpty else {
            var fallback = HomeLayout.default
            fallback.hidden = hidden.filter { placement in
                !fallback.widgets.contains { $0.widget == placement.widget }
            }
            return fallback
        }
        return HomeLayout(widgets: placed, hidden: hidden)
    }
}

/// Reads a tool one at a time, so one this build no longer has (Low Power and Lock Screen were removed) is dropped from a list instead
/// of failing it, and with it the widget it belongs to.
private struct LossyTool: Decodable {
    let value: ToolID?

    init(from decoder: Decoder) throws { value = try? ToolID(from: decoder) }
}

extension WidgetOptions {
    enum CodingKeys: String, CodingKey { case tools, timerMinutes, showsPomodoro, showsShelf, noteID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decodeIfPresent([LossyTool].self, forKey: .tools)?.compactMap(\.value)
        // Every tool gone means the choice is gone: follow the Tools row again.
        tools = stored?.isEmpty == true ? nil : stored
        timerMinutes = try container.decodeIfPresent([Int].self, forKey: .timerMinutes)
        showsPomodoro = try container.decodeIfPresent(Bool.self, forKey: .showsPomodoro)
        showsShelf = try container.decodeIfPresent(Bool.self, forKey: .showsShelf)
        noteID = try container.decodeIfPresent(UUID.self, forKey: .noteID)
    }
}
