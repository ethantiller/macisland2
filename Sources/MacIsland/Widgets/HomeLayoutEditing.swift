import Foundation

/// Where a dragged widget lands: before or after another in reading order.
enum HomeDropTarget: Equatable {
    case before(UUID)
    case after(UUID)
}

/// The menu's and the keys' Move commands.
enum HomeMove: Equatable {
    case up, down, left, right
}

/// The edits the Settings editor makes. Each returns the new layout, or nil when the edit would leave something off the
/// grid: a refused edit changes nothing. Pure, so all of it is tested.
extension HomeLayout {
    func index(of id: UUID) -> Int? { widgets.firstIndex { $0.id == id } }

    func placement(id: UUID) -> WidgetPlacement? {
        widgets.first { $0.id == id } ?? hidden.first { $0.id == id }
    }

    func isPlaced(_ widget: WidgetID) -> Bool { widgets.contains { $0.widget == widget } }

    /// Puts a placement (already on Home or off it, or new) at `index` in reading order.
    func inserting(
        _ placement: WidgetPlacement, at index: Int, catalog: Catalog = WidgetCatalog.descriptor(for:)
    ) -> HomeLayout? {
        // A widget appears once: another placement of the same widget can't come in.
        if widgets.contains(where: { $0.widget == placement.widget && $0.id != placement.id }) { return nil }
        guard let descriptor = catalog(placement.widget) else { return nil }
        var placement = placement
        placement.size = Self.repairedSize(placement.size, for: descriptor)

        var layout = self
        layout.widgets.removeAll { $0.id == placement.id }
        layout.hidden.removeAll { $0.id == placement.id || $0.widget == placement.widget }
        layout.widgets.insert(placement, at: min(max(index, 0), layout.widgets.count))
        return layout.isValid(catalog: catalog) ? layout : nil
    }

    /// Puts a placement before or after another.
    func placing(
        _ placement: WidgetPlacement, at target: HomeDropTarget, catalog: Catalog = WidgetCatalog.descriptor(for:)
    ) -> HomeLayout? {
        let id: UUID
        let offset: Int
        switch target {
        case .before(let other): (id, offset) = (other, 0)
        case .after(let other): (id, offset) = (other, 1)
        }
        if id == placement.id { return self }
        let others = widgets.filter { $0.id != placement.id }
        guard let spot = others.firstIndex(where: { $0.id == id }) else { return nil }
        return inserting(placement, at: spot + offset, catalog: catalog)
    }

    /// Moves a widget to the cell its top left is nearest: among the others (packed without it), it goes after the ones
    /// that start before that cell.
    func moving(
        _ id: UUID, toCell cell: GridCell, catalog: Catalog = WidgetCatalog.descriptor(for:)
    ) -> HomeLayout? {
        guard let placement = widgets.first(where: { $0.id == id }) else { return nil }
        var without = self
        without.widgets.removeAll { $0.id == id }
        let index = HomeGridSpec.insertionIndex(for: cell, among: without.rects(catalog: catalog))
        return inserting(placement, at: index, catalog: catalog)
    }

    /// One step: left and right are one place earlier or later in reading order; up and down put it a row above or below,
    /// in the same column.
    func moving(_ id: UUID, _ move: HomeMove, catalog: Catalog = WidgetCatalog.descriptor(for:)) -> HomeLayout? {
        guard let index = index(of: id), let placement = placement(id: id) else { return nil }
        let result: HomeLayout?
        switch move {
        case .left:
            result = index > 0 ? inserting(placement, at: index - 1, catalog: catalog) : nil
        case .right:
            result = index < widgets.count - 1 ? inserting(placement, at: index + 1, catalog: catalog) : nil
        case .up, .down:
            guard let rect = frames(catalog: catalog)[id] else { return nil }
            let row = rect.origin.row + (move == .up ? -1 : 1)
            guard row >= 0, row + rect.size.rows <= Theme.Metrics.homeMaxRows else { return nil }
            result = moving(id, toCell: GridCell(column: rect.origin.column, row: row), catalog: catalog)
        }
        return result == self ? nil : result
    }

    /// Changes a widget's size, if it has that size and everything still fits.
    func resizing(_ id: UUID, to size: GridSize, catalog: Catalog = WidgetCatalog.descriptor(for:)) -> HomeLayout? {
        guard let index = index(of: id), let descriptor = catalog(widgets[index].widget),
            descriptor.sizes.contains(size)
        else { return nil }
        var layout = self
        layout.widgets[index].size = size
        return layout.isValid(catalog: catalog) ? layout : nil
    }

    /// Takes a widget off Home, keeping its options and its size.
    func removing(_ id: UUID) -> HomeLayout {
        guard let index = index(of: id) else { return self }
        var layout = self
        let removed = layout.widgets.remove(at: index)
        layout.hidden.append(removed)
        // Home is never empty: removing the last widget keeps it.
        return layout.widgets.isEmpty ? self : layout
    }

    /// Adds a widget at `size` (its last size, or its default): into the earliest gap when nothing else moves,
    /// otherwise where it fits, or nil when there is no room.
    func adding(
        _ widget: WidgetID, size: GridSize? = nil, catalog: Catalog = WidgetCatalog.descriptor(for:)
    ) -> HomeLayout? {
        guard !isPlaced(widget), let descriptor = catalog(widget) else { return nil }
        var placement = hidden.first { $0.widget == widget } ?? WidgetPlacement(widget: widget)
        placement.size = size ?? (placement.size.isUnset ? descriptor.defaultSize : placement.size)

        let before = frames(catalog: catalog)
        var fallback: HomeLayout?
        for index in 0...widgets.count {
            guard let layout = inserting(placement, at: index, catalog: catalog) else { continue }
            let after = layout.frames(catalog: catalog)
            if before.allSatisfy({ after[$0.key] == $0.value }) { return layout }
            fallback = fallback ?? layout
        }
        return fallback
    }

    /// A preset in place of the widgets. Widgets the preset doesn't use, from Home and from off it, are kept off Home. Options
    /// survive for widgets that carry over, unless the preset is one the person saved, which brings its own.
    func applying(
        _ preset: HomeLayout, usesPresetOptions: Bool = false, catalog: Catalog = WidgetCatalog.descriptor(for:)
    ) -> HomeLayout {
        let known = widgets + hidden
        var layout = preset
        layout.widgets = preset.widgets.map { placement in
            var placement = placement
            if !usesPresetOptions, let existing = known.first(where: { $0.widget == placement.widget }) {
                placement.options = existing.options
            }
            return placement
        }
        let used = Set(layout.widgets.map(\.widget))
        layout.hidden = known.filter { !used.contains($0.widget) }
        return HomeLayout.normalized(layout, catalog: catalog)
    }

    /// Replaces one widget's options.
    func setting(_ options: WidgetOptions, for id: UUID) -> HomeLayout {
        var layout = self
        if let index = layout.widgets.firstIndex(where: { $0.id == id }) { layout.widgets[index].options = options }
        if let index = layout.hidden.firstIndex(where: { $0.id == id }) { layout.hidden[index].options = options }
        return layout
    }
}

extension HomeLayout {
    /// Everything that isn't on Home, to add: the built-ins and the person's own, including what was taken off, which comes back
    /// with the options and size it had.
    func addable(customs: [CustomWidget]) -> [WidgetID] {
        (BuiltInWidget.allCases.map { WidgetID.builtIn($0) } + customs.map { WidgetID.custom($0.id) })
            .filter { !isPlaced($0) }
    }
}

extension HomeLayout {
    /// Whether `widget` could be added at `size` right now: it isn't on Home, has that size, and everything would still fit. "No room"
    /// in the gallery is this, decided for each size.
    func fits(_ widget: WidgetID, size: GridSize, catalog: Catalog = WidgetCatalog.descriptor(for:)) -> Bool {
        catalog(widget)?.sizes.contains(size) == true && adding(widget, size: size, catalog: catalog) != nil
    }
}
