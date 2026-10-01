import AppKit
import Foundation

/// Which player's music the island shows (Content → Media). MediaRemote, through the vendored adapter, reports only the one app macOS
/// picked as the Now Playing app, so this doesn't choose between two players: it says whether a browser tab's video counts.
enum MediaSource: String, CaseIterable, Identifiable {
    case any = "Any App"
    case musicApps = "Music Apps Only"

    var id: Self { self }

    /// Apps that are music players whatever their Info.plist says.
    static let knownMusicApps: Set<String> = ["com.apple.Music", "com.apple.iTunes", "com.spotify.client"]

    /// Whether this source shows what `bundleID` is playing. `category` is the app's `LSApplicationCategoryType`, looked up only when
    /// needed.
    func accepts(bundleID: String?, category: (String) -> String? = MusicApps.category(of:)) -> Bool {
        switch self {
        case .any: return true
        case .musicApps:
            guard let bundleID, !bundleID.isEmpty else { return false }
            return Self.knownMusicApps.contains(bundleID) || category(bundleID) == "public.app-category.music"
        }
    }
}

enum MusicApps {
    nonisolated(unsafe) private static var categories: [String: String?] = [:]

    /// An app's declared category, remembered so the Info.plist is read once.
    static func category(of bundleID: String) -> String? {
        if let known = categories[bundleID] { return known }
        let value: String? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).flatMap {
            Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        }
        categories[bundleID] = .some(value)
        return value
    }
}

/// How long the pointer rests on the closed island before the peek opens (General → Input). The swell answers at once either way.
enum PeekDelay: String, CaseIterable, Identifiable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"

    var id: Self { self }

    var duration: Duration {
        switch self {
        case .short: Theme.Timing.peekDwell
        case .medium: .milliseconds(300)
        case .long: .milliseconds(600)
        }
    }
}

/// Which page the island opens on when it opens from closed (General → Input).
enum OpenOn: String, CaseIterable, Identifiable {
    case lastTab = "Last Tab"
    case home = "Home"
    case live = "What Is Live"

    var id: Self { self }
}
