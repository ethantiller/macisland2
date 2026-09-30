import AppKit

/// An installed app, found by name.
struct AppEntry: Identifiable, Hashable {
    let name: String
    let url: URL

    var id: URL { url }
}

enum AppIndex {
    static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// Every `.app` in the folders, and in one level of plain folders inside them (like Utilities or a vendor's
    /// folder). One entry per name, in name order.
    nonisolated static func scan(_ directories: [URL], fileManager: FileManager = .default) -> [AppEntry] {
        var found: [String: AppEntry] = [:]
        func visit(_ directory: URL, depth: Int) {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            for url in contents {
                if url.pathExtension == "app" {
                    let name = url.deletingPathExtension().lastPathComponent
                    if found[name.lowercased()] == nil { found[name.lowercased()] = AppEntry(name: name, url: url) }
                } else if depth < 1, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(url, depth: depth + 1)
                }
            }
        }
        directories.forEach { visit($0, depth: 0) }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
