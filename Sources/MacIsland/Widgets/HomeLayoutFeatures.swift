import Foundation

extension WidgetCatalog {
    /// The feature whose switch also switches this widget: off, the widget leaves Home. Today, Battery, and the widgets the person
    /// made belong to no feature.
    static func feature(of id: WidgetID) -> Feature? {
        guard case .builtIn(let widget) = id else { return nil }
        switch widget {
        case .music: return .music
        case .clockActions: return .clock
        case .quickTools: return .tools
        case .weather: return .weather
        case .reminders: return .reminders
        case .note: return .notes
        case .system: return .system
        case .today, .battery: return nil
        }
    }
}

/// Widgets move off Home when their feature is switched off, and come back when it is switched on. Pure, so it is tested like the
/// rest of the layout.
extension HomeLayout {
    /// Takes every widget that `isOff` says is off Home, keeping its size and options in `hidden`, and returns the widgets taken. Home
    /// is never empty: when everything on it would leave, Today comes first. A widget that can't leave stays.
    func removingWidgets(
        where isOff: (WidgetID) -> Bool, catalog: Catalog = WidgetCatalog.descriptor(for:)
    ) -> (layout: HomeLayout, taken: [WidgetID]) {
        let leaving = widgets.filter { isOff($0.widget) }
        guard !leaving.isEmpty else { return (self, []) }
        var layout = self
        if leaving.count == widgets.count {
            guard let withToday = layout.adding(.builtIn(.today), catalog: catalog) else { return (self, []) }
            layout = withToday
        }
        var taken: [WidgetID] = []
        for placement in leaving {
            let next = layout.removing(placement.id)
            if next != layout { taken.append(placement.widget) }
            layout = next
        }
        return (layout, taken)
    }

    /// Puts back each of `widgets` that is off Home: the first spot it fits, at its last size. One that has no room stays in Add
    /// Widgets, and is not reported as restored.
    func restoring(_ widgets: [WidgetID], catalog: Catalog = WidgetCatalog.descriptor(for:)) -> HomeLayout {
        var layout = self
        for widget in widgets where !layout.isPlaced(widget) {
            if let next = layout.adding(widget, catalog: catalog) { layout = next }
        }
        return layout
    }
}
