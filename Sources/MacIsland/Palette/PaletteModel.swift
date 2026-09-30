import AppKit
import Observation
import SwiftUI
import Translation

/// One row in the command palette.
struct PaletteItem: Identifiable {
    enum Icon {
        case symbol(String)
        case app(URL)
    }

    let id: String
    var title: String
    var subtitle: String?
    var icon: Icon
    /// Stay open after running, for a row that only starts something (a translation).
    var keepsOpen = false
    let run: @MainActor () -> Void
}

enum TranslationState: Equatable {
    case idle
    case working(TranslationRequest)
    case done(TranslationRequest, String)
    case failed(TranslationRequest)
}

/// What the command palette shows for what is typed: modules, tools, timers, apps, Shortcuts, snippets, web
/// searches, and translation.
@MainActor
@Observable
final class PaletteModel {
    static let maxResults = 8

    private let viewModel: IslandViewModel

    var query = "" {
        didSet { if query != oldValue { update() } }
    }
    private(set) var results: [PaletteItem] = []
    var selection = 0
    private(set) var translation = TranslationState.idle
    var translationConfiguration: TranslationSession.Configuration?

    /// Closes the palette. Set by whoever shows it.
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        update()
    }

    private var settings: AppSettings { viewModel.settings }

    func reset() {
        query = ""
        translation = .idle
        translationConfiguration = nil
        update()
    }

    func moveSelection(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + step + results.count) % results.count
    }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        item.run()
        if !item.keepsOpen { onClose?() }
    }

    // MARK: Results

    func update() {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            results = Array(suggestions().prefix(Self.maxResults))
        } else {
            let special = specialItems(for: text)
            let fallback = searchItem(engine: settings.defaultSearchEngine, query: text)
            let room = max(Self.maxResults - special.count - 1, 0)
            results = special + Array(matches(for: text).prefix(room)) + [fallback]
        }
        selection = 0
    }

    /// Nothing typed: every module, to jump to.
    private func suggestions() -> [PaletteItem] {
        IslandModule.allCases.filter(\.isAvailable).map(moduleItem)
    }

    /// Rows that read the whole text: a timer, a reminder, a keyword search, a translation.
    private func specialItems(for text: String) -> [PaletteItem] {
        var items: [PaletteItem] = []

        if let minutes = PaletteTimer.minutes(from: text) {
            items.append(PaletteItem(
                id: "timer", title: "Start a \(minutes)-minute timer", subtitle: "Timer", icon: .symbol("timer")
            ) { [viewModel] in viewModel.timer.start(minutes: minutes) })
        }

        let lowered = text.lowercased()
        for prefix in ["remind ", "todo "] where lowered.hasPrefix(prefix) {
            let title = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                items.append(PaletteItem(
                    id: "remind", title: "Add Reminder \u{201C}\(title)\u{201D}", subtitle: "Reminders", icon: .symbol("checklist")
                ) { [viewModel] in viewModel.addReminder(title) })
            }
        }

        if let query = Self.clipboardQuery(from: text) {
            items += clipboardItems(matching: query)
        }

        if let match = SearchEngine.match(text, in: settings.searchEngines) {
            items.append(searchItem(engine: match.engine, query: match.query))
        }

        if let request = TranslationRequest.parse(text) {
            items.append(translationItem(for: request))
        }
        return items
    }

    /// `clip foo` or `cb foo`: what follows the keyword. Just the keyword asks for the recent copies.
    nonisolated static func clipboardQuery(from text: String) -> String? {
        let lowered = text.lowercased()
        for keyword in ["clip", "cb"] {
            if lowered == keyword { return "" }
            if lowered.hasPrefix(keyword + " ") { return String(text.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    private static let clipboardRows = 5

    /// Copied text that matches, newest first. Return copies one back.
    private func clipboardItems(matching query: String) -> [PaletteItem] {
        viewModel.clipboard.matches(query).prefix(Self.clipboardRows).compactMap { entry in
            guard case .text(let text) = entry.content else { return nil }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
            return PaletteItem(
                id: "clip-\(entry.id)", title: String(line.prefix(70)), subtitle: "Clipboard \u{00B7} Return to copy",
                icon: .symbol("doc.on.clipboard")
            ) { [viewModel] in viewModel.copyFromClipboardHistory(entry) }
        }
    }

    private func searchItem(engine: SearchEngine, query: String) -> PaletteItem {
        PaletteItem(
            id: "search-\(engine.id)",
            title: "Search \(engine.name) for \u{201C}\(query)\u{201D}",
            subtitle: "Web",
            icon: .symbol("magnifyingglass")
        ) {
            if let url = engine.url(for: query) { NSWorkspace.shared.open(url) }
        }
    }

    private func translationItem(for request: TranslationRequest) -> PaletteItem {
        switch translation {
        case .working(let working) where working == request:
            return PaletteItem(
                id: "translate", title: "Translating\u{2026}", subtitle: request.targetName,
                icon: .symbol("translate"), keepsOpen: true
            ) {}
        case .done(let done, let output) where done == request:
            return PaletteItem(
                id: "translate", title: output, subtitle: "Return to copy \u{00B7} \(request.targetName)", icon: .symbol("translate")
            ) { [viewModel] in
                SystemActions.copyToClipboard(output)
                viewModel.flash(
                    IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"),
                    respectingFocus: false
                )
            }
        case .failed(let failed) where failed == request:
            return PaletteItem(
                id: "translate", title: "Couldn\u{2019}t translate. Try again", subtitle: request.targetName,
                icon: .symbol("translate"), keepsOpen: true
            ) { [weak self] in self?.beginTranslation(request) }
        default:
            return PaletteItem(
                id: "translate", title: "Translate to \(request.targetName)", subtitle: "\u{201C}\(request.text)\u{201D}",
                icon: .symbol("translate"), keepsOpen: true
            ) { [weak self] in self?.beginTranslation(request) }
        }
    }

    func beginTranslation(_ request: TranslationRequest) {
        translation = .working(request)
        translationConfiguration = .init(source: nil, target: Locale.Language(identifier: request.target))
        update()
    }

    func finishTranslation(_ request: TranslationRequest, output: String?) {
        translation = output.map { .done(request, $0) } ?? .failed(request)
        update()
    }

    // MARK: Matching

    private struct Candidate {
        let item: PaletteItem
        let names: [String]
        /// Nudges one kind of result above another when they match equally well.
        let bias: Double
    }

    private func matches(for text: String) -> [PaletteItem] {
        candidates()
            .compactMap { candidate -> (PaletteItem, Double)? in
                PaletteSearch.bestScore(query: text, in: candidate.names).map { (candidate.item, $0 + candidate.bias) }
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func candidates() -> [Candidate] {
        var list: [Candidate] = []

        for module in IslandModule.allCases where module.isAvailable {
            list.append(Candidate(item: moduleItem(module), names: [module.title, module.rawValue], bias: 50))
            list.append(Candidate(
                item: PaletteItem(
                    id: "window-\(module.rawValue)", title: "Open \(module.title) in a Window", subtitle: "Window",
                    icon: .symbol("macwindow")
                ) { [viewModel] in viewModel.openWindow(module) },
                names: ["\(module.title) window", "detach \(module.title)", "float \(module.title)"], bias: -150
            ))
            let inBar = settings.isInMenuBar(module)
            list.append(Candidate(
                item: PaletteItem(
                    id: "menubar-\(module.rawValue)",
                    title: inBar ? "Hide \(module.title) from the Menu Bar" : "Show \(module.title) in the Menu Bar",
                    subtitle: "Menu Bar", icon: .symbol("menubar.rectangle")
                ) { [settings] in settings.setInMenuBar(module, !inBar) },
                names: ["\(module.title) menu bar"], bias: -150
            ))
        }

        let catalog = ToolCatalog(viewModel: viewModel)
        for id in ToolID.allCases {
            let tool = catalog.item(for: id)
            list.append(Candidate(
                item: PaletteItem(
                    id: "tool-\(id.rawValue)", title: tool.title, subtitle: tool.isOn ? "Tool \u{00B7} On" : "Tool",
                    icon: .symbol(tool.systemImage)
                ) { tool.action() },
                names: [tool.title], bias: 30
            ))
        }

        list.append(Candidate(
            item: PaletteItem(id: "new-note", title: "New Note", subtitle: "Notes", icon: .symbol("square.and.pencil")) {
                [viewModel] in
                viewModel.openQuickNote()
                viewModel.open()
            },
            names: ["new note", "note"], bias: 20
        ))
        list.append(Candidate(
            item: PaletteItem(id: "settings", title: "Settings", subtitle: "MacIsland", icon: .symbol("gearshape")) {
                [weak self] in self?.onOpenSettings?()
            },
            names: ["settings", "preferences"], bias: 20
        ))

        for app in viewModel.launch.apps {
            list.append(Candidate(
                item: PaletteItem(id: "app-\(app.url.path)", title: app.name, subtitle: "App", icon: .app(app.url)) {
                    [launch = viewModel.launch] in launch.open(app.url)
                },
                names: [app.name], bias: 0
            ))
        }

        for name in viewModel.launch.shortcuts {
            list.append(Candidate(
                item: PaletteItem(id: "shortcut-\(name)", title: "Run \u{201C}\(name)\u{201D}", subtitle: "Shortcut", icon: .symbol("square.2.layers.3d")) {
                    [viewModel] in viewModel.runShortcut(name)
                },
                names: [name, "shortcut \(name)"], bias: 0
            ))
        }

        for snippet in viewModel.notes.snippets {
            let title = snippet.title.isEmpty ? String(snippet.text.prefix(40)) : snippet.title
            guard !title.isEmpty else { continue }
            list.append(Candidate(
                item: PaletteItem(id: "snippet-\(snippet.id)", title: title, subtitle: "Copy snippet", icon: .symbol("text.badge.plus")) {
                    [viewModel] in viewModel.copySnippet(snippet)
                },
                names: [title, snippet.text], bias: -10
            ))
        }
        return list
    }

    private func moduleItem(_ module: IslandModule) -> PaletteItem {
        PaletteItem(
            id: "module-\(module.rawValue)", title: "Open \(module.title)", subtitle: nil, icon: .symbol(module.systemImage)
        ) { [viewModel] in viewModel.show(module) }
    }
}
