import AppKit
import Foundation

/// A Home layout in a file (`Home.macislandhome.json`), to share or keep: the layout, and the custom widgets it
/// uses. **Command widgets are never in one**, going out or coming in: a file from anyone else must not be able to
/// make this Mac run a program.
struct HomeArchive: Codable, Equatable {
    static let format = "MacIsland Home"
    static let currentVersion = 2

    var format = HomeArchive.format
    var version = HomeArchive.currentVersion
    var layout: HomeLayout
    var widgets: [CustomWidget] = []

    enum CodingKeys: String, CodingKey { case format, version, layout, widgets }

    init(layout: HomeLayout, widgets: [CustomWidget] = []) {
        self.layout = layout
        self.widgets = widgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        layout = try container.decode(HomeLayout.self, forKey: .layout)
        widgets =
            (try? container.decodeIfPresent([Lossy<CustomWidget>].self, forKey: .widgets))?.compactMap(\.value) ?? []
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    enum ReadError: LocalizedError, Equatable {
        case notAnArchive, tooNew

        var errorDescription: String? {
            switch self {
            case .notAnArchive: "That isn\u{2019}t a MacIsland Home file."
            case .tooNew: "That file is from a newer MacIsland."
            }
        }
    }

    // MARK: Writing

    /// The layout and the custom widgets it uses, without commands (and without the places they held).
    static func make(layout: HomeLayout, customs: [CustomWidget]) -> HomeArchive {
        let commands = Set(customs.filter(\.isCommand).map { WidgetID.custom($0.id) })
        var stripped = layout
        stripped.widgets = layout.widgets.filter { !commands.contains($0.widget) }
        stripped.hidden = layout.hidden.filter { !commands.contains($0.widget) }
        let used = Set((stripped.widgets + stripped.hidden).map(\.widget))
        return HomeArchive(layout: stripped, widgets: customs.filter { !$0.isCommand && used.contains(.custom($0.id)) })
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Reading

    static func read(_ data: Data) throws -> HomeArchive {
        guard let archive = try? JSONDecoder().decode(HomeArchive.self, from: data), archive.format == format else {
            throw ReadError.notAnArchive
        }
        guard archive.version <= currentVersion else { throw ReadError.tooNew }
        return archive
    }

    /// What importing would do: the widgets (each with a new id, commands dropped), the repaired layout, and a
    /// sentence for the confirmation.
    struct ImportPlan: Equatable {
        var layout: HomeLayout
        var widgets: [CustomWidget]
        var summary: String
    }

    func importPlan() -> ImportPlan {
        var renamed: [UUID: CustomWidget] = [:]
        for widget in widgets where !widget.isCommand && widget.isValid {
            var copy = widget
            copy.id = UUID()
            renamed[widget.id] = copy
        }
        func remap(_ placement: WidgetPlacement) -> WidgetPlacement? {
            guard case .custom(let old) = placement.widget else { return placement }
            guard let new = renamed[old] else { return nil }
            var copy = placement
            copy.widget = .custom(new.id)
            return copy
        }
        var mapped = layout
        mapped.widgets = layout.widgets.compactMap(remap)
        mapped.hidden = layout.hidden.compactMap(remap)
        let added = Array(renamed.values).sorted { $0.title < $1.title }
        let catalog: HomeLayout.Catalog = { WidgetCatalog.descriptor(for: $0, customs: added) }
        return ImportPlan(
            layout: HomeLayout.normalized(mapped, catalog: catalog), widgets: added, summary: Self.summary(of: added))
    }

    static func summary(of widgets: [CustomWidget]) -> String {
        guard !widgets.isEmpty else { return "This uses only the built-in widgets." }
        let list = widgets.map { widget in
            "\(widget.title) (\(widget.webHost ?? widget.kindName.lowercased()))"
        }.joined(separator: ", ")
        return "Adds \(widgets.count) widget\(widgets.count == 1 ? "" : "s"): \(list)"
    }
}

/// The panels and confirmations around export, import, and reset. Kept out of `HomeEditor` so that stays testable.
@MainActor
enum HomeArchivePanels {
    static func export(_ layout: HomeLayout, customs: [CustomWidget]) {
        let archive = HomeArchive.make(layout: layout, customs: customs)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Home.macislandhome.json"
        panel.allowedContentTypes = [.json]
        var message = "Command widgets are not included."
        let hosts = Set(archive.widgets.compactMap(\.webHost)).sorted()
        if !hosts.isEmpty { message += " Web widgets are: they ask \(hosts.joined(separator: ", "))." }
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try archive.data().write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Reads a file and, after confirming, returns what to apply.
    static func importPlan() -> HomeArchive.ImportPlan? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let plan = try HomeArchive.read(Data(contentsOf: url)).importPlan()
            let alert = NSAlert()
            alert.messageText = "Replace Your Home Layout?"
            alert.informativeText =
                "\(plan.summary)\n\nThis uses the layout in \u{201C}\(url.lastPathComponent)\u{201D}. You can undo it."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn ? plan : nil
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    static func confirmReset() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Reset Home to Everyday?"
        alert.informativeText = "Home goes back to its default layout. Widget options are kept. You can undo it."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
