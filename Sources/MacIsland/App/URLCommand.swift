import AppKit

/// What a `macisland://` link asks for. `parse` enforces the limits, so anything it returns is safe to run.
enum URLCommand: Equatable {
    case timer(minutes: Int)
    case stopwatch
    case pomodoro
    case open(IslandModule)
    case addToShelf(URL)
    case banner(title: String, detail: String?, symbol: String?)
    /// Shows the first-run guide again. `reset` (debug builds only) first makes this install a fresh one.
    case guide(reset: Bool)
    /// Opens Settings on its tour.
    case settingsTour

    static let maxMinutes = 1440
    static let titleLimit = 60
    static let detailLimit = 80

    /// `timer?minutes=`, `stopwatch`, `pomodoro`, `open?module=`, `shelf/add?path=`,
    /// `banner?title=&detail=&symbol=`, `guide` (and, in debug builds, `guide?reset=1`), and `tour`. Anything else is `nil`.
    nonisolated static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "macisland",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let name = ((components.host ?? "") + components.path).lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name.lowercased()] = item.value ?? "" }

        switch name {
        case "timer":
            guard let minutes = query["minutes"].flatMap({ Int($0) }), (1...maxMinutes).contains(minutes) else {
                return nil
            }
            return .timer(minutes: minutes)
        case "stopwatch":
            return .stopwatch
        case "pomodoro":
            return .pomodoro
        case "open":
            guard let module = IslandModule.allCases.first(where: { $0.rawValue == query["module"]?.lowercased() }),
                module.isAvailable
            else { return nil }
            return .open(module)
        case "shelf/add":
            guard let path = query["path"], path.hasPrefix("/") else { return nil }
            let file = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return .addToShelf(file)
        case "banner":
            let title = String(
                (query["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(titleLimit))
            guard !title.isEmpty else { return nil }
            let detail = String(
                (query["detail"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(detailLimit))
            return .banner(
                title: title, detail: detail.isEmpty ? nil : detail,
                symbol: query["symbol"].flatMap { isSymbolName($0) ? $0 : nil }
            )
        case "guide":
            #if DEBUG
                return .guide(reset: query["reset"] == "1")
            #else
                return .guide(reset: false)
            #endif
        case "tour":
            return .settingsTour
        default:
            return nil
        }
    }

    /// An SF Symbol name is lowercase letters, digits, and dots.
    private nonisolated static func isSymbolName(_ name: String) -> Bool {
        (1...60).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") }
    }
}

/// Runs the links the app is opened with. Banners are neutral, carry no actions, and come at most once
/// every two seconds, so a link can't be used to spam the notch.
@MainActor
final class URLCommandRunner {
    static let bannerInterval: TimeInterval = 2

    private let viewModel: IslandViewModel
    private let now: () -> Date
    private var lastBanner: Date?
    /// Set by the app, which owns the guide and Settings. Both only show UI, so a link can't do harm with them.
    var onGuide: ((_ reset: Bool) -> Void)?
    var onTour: (() -> Void)?

    init(viewModel: IslandViewModel, now: @escaping () -> Date = Date.init) {
        self.viewModel = viewModel
        self.now = now
    }

    func handle(_ urls: [URL]) {
        for url in urls {
            if let command = URLCommand.parse(url) { run(command) }
        }
    }

    func run(_ command: URLCommand) {
        switch command {
        case .timer(let minutes):
            viewModel.timer.start(minutes: minutes)
        case .stopwatch:
            if !viewModel.stopwatch.isRunning { viewModel.stopwatch.toggle() }
        case .pomodoro:
            if !viewModel.pomodoro.isActive { viewModel.pomodoro.toggle() }
        case .open(let module):
            // A module whose feature is off has no page to open.
            if viewModel.settings.isShown(module) { viewModel.show(module) }
        case .addToShelf(let url):
            viewModel.shelf.add([url])
            viewModel.flash(
                IslandAlert(systemImage: "tray.and.arrow.down.fill", tint: Theme.Tint.neutral, text: "Shelf"),
                respectingFocus: false)
        case .guide(let reset):
            onGuide?(reset)
        case .settingsTour:
            onTour?()
        case .banner(let title, let detail, let symbol):
            if let lastBanner, now().timeIntervalSince(lastBanner) < Self.bannerInterval { return }
            lastBanner = now()
            let glyph = symbol.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil ? $0 : nil
            }
            viewModel.showBanner(
                IslandBanner(systemImage: glyph ?? "bell.fill", tint: Theme.Tint.neutral, title: title, detail: detail),
                for: .seconds(5)
            )
        }
    }
}
