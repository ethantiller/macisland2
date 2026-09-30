import AppKit
import Observation

/// Every installed app and the person's Shortcuts, for the command palette to search.
@MainActor
@Observable
final class LaunchModel {
    private(set) var apps: [AppEntry] = []
    private(set) var shortcuts: [String] = []

    @ObservationIgnored private let directories: [URL]
    @ObservationIgnored private var appsLoaded = false
    @ObservationIgnored private var shortcutsLoadedAt: Date?

    init(appDirectories: [URL] = AppIndex.defaultDirectories) {
        directories = appDirectories
    }

    /// Scans the app folders once, off the main thread.
    func loadApps() async {
        guard !appsLoaded else { return }
        appsLoaded = true
        let directories = directories
        apps = await Task.detached { AppIndex.scan(directories) }.value
    }

    /// Reads the Shortcuts list, at most once a minute.
    func refreshShortcuts() async {
        if let last = shortcutsLoadedAt, Date().timeIntervalSince(last) < 60 { return }
        shortcutsLoadedAt = Date()
        shortcuts = await ShortcutsCLI.list()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
