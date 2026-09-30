import AppKit
import Foundation

/// A widget the person made. It is one of four kinds, shown as white text with a glyph: color is never the
/// person's to choose. It turns blue only while updating and red only when an update fails.
struct CustomWidget: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// An SF Symbol name, checked with `isValidSymbol`.
    var systemImage: String
    var source: Source
    /// How old a value may get before opening Home fetches it again. At least `Self.minimumMaxAge`.
    var maxAgeMinutes = CustomWidget.defaultMaxAge

    enum Source: Codable, Equatable {
        /// `showsResult` false is a button that runs it.
        case shortcut(name: String, showsResult: Bool)
        /// One HTTPS request; `path` picks a value out of JSON, or the first line of text when nil.
        case web(url: URL, path: String?)
        /// The file count and the newest name. A click opens it.
        case folder(path: String)
        /// A file you chose. Stays on this Mac: never exported or imported.
        case command(path: String)
    }

    static let minimumMaxAge = 5
    static let defaultMaxAge = 15

    var maxAge: Duration { .seconds(max(maxAgeMinutes, Self.minimumMaxAge) * 60) }

    var isCommand: Bool {
        if case .command = source { return true }
        return false
    }

    /// A button, not a value: it runs a Shortcut when clicked and never fetches.
    var isButton: Bool {
        if case .shortcut(_, let showsResult) = source { return !showsResult }
        return false
    }

    /// The host a web widget talks to, for the Privacy pane.
    var webHost: String? {
        if case .web(let url, _) = source { return url.host }
        return nil
    }

    static func isValidSymbol(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// Only HTTPS, and with a host.
    static func isValidWebURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && (url.host?.isEmpty == false)
    }

    /// Whether this can be saved: a name, a real symbol, and a source that makes sense.
    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, Self.isValidSymbol(systemImage) else { return false }
        switch source {
        case .shortcut(let name, _): return !name.isEmpty
        case .web(let url, _): return Self.isValidWebURL(url)
        case .folder(let path), .command(let path): return path.hasPrefix("/")
        }
    }

    var kindName: String {
        switch source {
        case .shortcut: "Shortcut"
        case .web: "Web Value"
        case .folder: "Folder"
        case .command: "Command"
        }
    }

    var descriptor: WidgetDescriptor {
        let kind: WidgetSource
        let tap: WidgetTap
        switch source {
        case .shortcut(_, let showsResult):
            kind = .shortcut
            tap = showsResult ? .custom : .runShortcut
        case .web:
            kind = .web
            tap = .custom
        case .folder:
            kind = .folder
            tap = .openFolder
        case .command:
            kind = .command
            tap = .custom
        }
        return WidgetDescriptor(
            id: .custom(id), title: title, systemImage: systemImage, sizes: sizes, defaultSize: GridSize(2, 1),
            source: kind, refresh: isButton ? .onTap : .onAppear(maxAge: maxAge), tint: .working, tap: tap)
    }

    /// A button has two sizes; a value, folder, or command has three. The size belongs to the placement.
    var sizes: [GridSize] {
        isButton ? [GridSize(1, 1), GridSize(2, 1)] : [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1)]
    }
}

extension WidgetCatalog {
    /// Any widget: a built-in, or one of the person's own.
    static func descriptor(for id: WidgetID, customs: [CustomWidget]) -> WidgetDescriptor? {
        if case .custom(let uuid) = id { return customs.first { $0.id == uuid }?.descriptor }
        return descriptor(for: id)
    }
}

/// Picking a value out of a web response. Pure.
enum WebValue {
    /// The longest a shown value gets.
    static let maxLength = 60

    /// With a `path` ("data.0.price"), that value in the JSON body: names pick a key, numbers an item. Without
    /// one, the first non-empty line of the text. Nil when nothing is there.
    static func extract(_ body: Data, path: String?) -> String? {
        let path = path?.trimmingCharacters(in: .whitespaces) ?? ""
        if path.isEmpty {
            let text = String(decoding: body, as: UTF8.self)
            let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first {
                !$0.isEmpty
            }
            return line.map { String($0.prefix(maxLength)) }
        }
        guard var node = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else { return nil }
        for step in path.split(separator: ".").map(String.init) {
            if let object = node as? [String: Any], let next = object[step] {
                node = next
            } else if let array = node as? [Any], let index = Int(step), array.indices.contains(index) {
                node = array[index]
            } else {
                return nil
            }
        }
        return describe(node)
    }

    private static func describe(_ node: Any) -> String? {
        switch node {
        case let string as String: return String(string.prefix(maxLength))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "Yes" : "No" }
            return number.stringValue
        default: return nil
        }
    }
}
