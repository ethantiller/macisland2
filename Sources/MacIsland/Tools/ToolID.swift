import Foundation

/// A tool the Tools tab can show: one of the nine built in, or a tool the person made from one of their Shortcuts. The raw value is
/// what is stored and dragged: a built-in's own name ("keepAwake"), or `shortcut:` and the UUID of its `ShortcutTool`. The built-ins
/// are static members, so `.keepAwake` reads as it did when this was an enum; `allCases` is the built-ins only, and
/// `AppSettings.allTools` adds the person's own.
struct ToolID: Hashable, Identifiable, RawRepresentable, Codable, Sendable {
    let rawValue: String

    private init(unchecked rawValue: String) { self.rawValue = rawValue }

    /// Nil for a name that is neither a built-in nor a well-formed Shortcut tool.
    init?(rawValue: String) {
        guard Self.builtInNames.contains(rawValue) || Self.shortcutUUID(in: rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    /// The tool made from a `ShortcutTool`.
    init(shortcut id: UUID) { rawValue = Self.shortcutPrefix + id.uuidString }

    var id: String { rawValue }

    static let keepAwake = ToolID(unchecked: "keepAwake")
    static let ringLight = ToolID(unchecked: "ringLight")
    static let muteMic = ToolID(unchecked: "muteMic")
    static let pickColor = ToolID(unchecked: "pickColor")
    static let screenshot = ToolID(unchecked: "screenshot")
    static let focus = ToolID(unchecked: "focus")
    static let cleanKeyboard = ToolID(unchecked: "cleanKeyboard")
    static let mirror = ToolID(unchecked: "mirror")
    static let recordScreen = ToolID(unchecked: "recordScreen")

    /// The built-in tools, in the order the Tools tab shows them.
    static let allCases: [ToolID] = [
        .keepAwake, .ringLight, .muteMic, .pickColor, .screenshot, .focus, .cleanKeyboard, .mirror, .recordScreen,
    ]

    private static let builtInNames = Set(allCases.map(\.rawValue))
    private static let shortcutPrefix = "shortcut:"

    static let defaultPins: [ToolID] = [.keepAwake, .ringLight, .muteMic, .screenshot, .pickColor, .focus]

    /// Every tool with the default pins first: what fills a Quick Tools slot nobody chose.
    static let fillOrder: [ToolID] = defaultPins + allCases.filter { !defaultPins.contains($0) }

    /// The tool a `ShortcutTool` makes, or nil for a built-in.
    var shortcutID: UUID? { Self.shortcutUUID(in: rawValue) }

    var isBuiltIn: Bool { Self.builtInNames.contains(rawValue) }

    private static func shortcutUUID(in raw: String) -> UUID? {
        guard raw.hasPrefix(shortcutPrefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(shortcutPrefix.count)))
    }
}

/// A tool made from one of the person's Shortcuts: pressing it runs the Shortcut. Its icon is an SF Symbol the person picks; the icon
/// the Shortcuts app shows for it can't be read honestly (see docs/plans/shortcut-icons.md).
struct ShortcutTool: Codable, Identifiable, Equatable {
    static let defaultSymbol = "bolt.fill"
    /// The label sits under a round button in a grid of six, so it stays short.
    static let maxTitleLength = 14

    var id = UUID()
    /// The Shortcut's name, as Shortcuts lists it.
    var shortcut: String
    /// What the tool is called.
    var title: String
    /// An SF Symbol name.
    var systemImage = ShortcutTool.defaultSymbol

    var toolID: ToolID { ToolID(shortcut: id) }

    /// The name and label are trimmed and the label cut to `maxTitleLength`.
    var cleaned: ShortcutTool {
        var tool = self
        tool.shortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        tool.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTitleLength))
        return tool
    }

    /// Whether it can be saved: a Shortcut, a label, and a real symbol.
    var isValid: Bool {
        let tool = cleaned
        return !tool.shortcut.isEmpty && !tool.title.isEmpty && CustomWidget.isValidSymbol(tool.systemImage)
    }
}
