import CoreGraphics
import Foundation

/// The widgets MacIsland ships for Home. Each reuses an existing view or model.
enum BuiltInWidget: String, CaseIterable, Codable {
    // Today's four.
    case today, music, quickTools, clockActions
    // New, each reusing a view or a model that exists.
    case weather, battery, reminders, note
    // Off until the System feature is switched on.
    case system
    // Off until AI Agents is switched on.
    case agents
}

/// One widget in a layout: one of the built-ins, or one the person made.
enum WidgetID: Hashable, Codable {
    case builtIn(BuiltInWidget)
    case custom(UUID)

    private static let customPrefix = "custom:"

    /// A single string, so a stored layout reads plainly and an unknown widget decodes to something to repair.
    var rawValue: String {
        switch self {
        case .builtIn(let widget): widget.rawValue
        case .custom(let id): Self.customPrefix + id.uuidString
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix(Self.customPrefix),
            let id = UUID(uuidString: String(rawValue.dropFirst(Self.customPrefix.count)))
        {
            self = .custom(id)
        } else if let widget = BuiltInWidget(rawValue: rawValue) {
            self = .builtIn(widget)
        } else {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let id = WidgetID(rawValue: value) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown widget \(value)"))
        }
        self = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What a widget reads. The Privacy pane and the idle budget are written from this.
enum WidgetSource: Equatable {
    case agenda, nowPlaying, pinnedTools, clock, weather, battery, reminders, notes, system, agents
    case shortcut, web, folder, command
}

/// When a widget's data updates. Nothing here is a background schedule: everything is push, or happens only
/// while Home is on screen.
enum WidgetRefresh: Equatable {
    case push
    case whileVisible(Duration)
    case onAppear(maxAge: Duration)
    case onTap
}

/// The one live meaning a widget may show in color. Color is never the person's to choose.
enum WidgetTint: Equatable {
    case none, clock, working, positive, attention, artwork
}

/// What a click on a widget does.
enum WidgetTap: Equatable {
    case openModule(IslandModule)
    case runShortcut
    case openURL
    case openFolder
    case custom
}

struct WidgetDescriptor: Equatable {
    let id: WidgetID
    let title: String
    let systemImage: String
    /// The sizes this widget has a layout for, in the order the editor offers them.
    let sizes: [GridSize]
    let defaultSize: GridSize
    let source: WidgetSource
    let refresh: WidgetRefresh
    let tint: WidgetTint
    let tap: WidgetTap?
}

enum WidgetCatalog {
    static func descriptor(builtIn widget: BuiltInWidget) -> WidgetDescriptor {
        func make(
            _ title: String, _ image: String, sizes: [GridSize], default defaultSize: GridSize,
            source: WidgetSource, refresh: WidgetRefresh = .push, tint: WidgetTint = .none, tap: WidgetTap? = nil
        ) -> WidgetDescriptor {
            WidgetDescriptor(
                id: .builtIn(widget), title: title, systemImage: image, sizes: sizes, defaultSize: defaultSize,
                source: source, refresh: refresh, tint: tint, tap: tap)
        }
        switch widget {
        case .today:
            return make(
                "Today", "calendar", sizes: [GridSize(2, 1), GridSize(3, 1), GridSize(3, 2), GridSize(3, 3)],
                default: GridSize(3, 1), source: .agenda, refresh: .whileVisible(.seconds(30)), tap: .custom)
        case .music:
            return make(
                "Music", "music.note",
                sizes: [GridSize(2, 1), GridSize(3, 1), GridSize(6, 1), GridSize(3, 2), GridSize(6, 2)],
                default: GridSize(3, 1), source: .nowPlaying, tint: .artwork, tap: .openModule(.media))
        case .quickTools:
            return make(
                "Quick Tools", "square.grid.2x2",
                sizes: [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1), GridSize(6, 1), GridSize(6, 2)],
                default: GridSize(1, 1), source: .pinnedTools, tap: .custom)
        case .clockActions:
            return make(
                "Timers & Shelf", "timer",
                sizes: [GridSize(2, 1), GridSize(3, 1), GridSize(4, 1), GridSize(5, 1), GridSize(6, 1)],
                default: GridSize(5, 1), source: .clock, refresh: .whileVisible(.seconds(1)), tint: .clock,
                tap: .custom)
        case .weather:
            return make(
                "Weather", "cloud.sun",
                sizes: [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1), GridSize(6, 1), GridSize(3, 2)],
                default: GridSize(1, 1), source: .weather)
        case .battery:
            return make(
                "Battery", "battery.75percent", sizes: [GridSize(1, 1), GridSize(2, 1)], default: GridSize(1, 1),
                source: .battery, refresh: .onAppear(maxAge: .seconds(60)), tint: .attention)
        case .reminders:
            return make(
                "Reminders", "checklist",
                sizes: [GridSize(2, 1), GridSize(3, 1), GridSize(3, 2), GridSize(6, 2)], default: GridSize(3, 1),
                source: .reminders, tap: .openModule(.reminders))
        case .note:
            return make(
                "Note", "note.text", sizes: [GridSize(2, 1), GridSize(3, 1), GridSize(3, 2), GridSize(6, 2)],
                default: GridSize(3, 1), source: .notes, tap: .openModule(.notes))
        case .system:
            return make(
                "System", "cpu", sizes: [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1), GridSize(3, 2)],
                default: GridSize(2, 1), source: .system, refresh: .whileVisible(.seconds(2)), tint: .attention)
        case .agents:
            return make(
                "AI Agents", "sparkles", sizes: [GridSize(2, 1), GridSize(3, 1)], default: GridSize(3, 1),
                source: .agents, tint: .attention, tap: .openModule(.agents))
        }
    }

    /// The descriptor for any widget this build knows.
    static func descriptor(for id: WidgetID) -> WidgetDescriptor? {
        if case .builtIn(let widget) = id { return descriptor(builtIn: widget) }
        return nil
    }
}
