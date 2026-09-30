import CoreServices
import Foundation

/// The players that can be asked about their own volume, and about favorites, through AppleScript.
enum ScriptablePlayer: String {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    init?(bundleIdentifier: String?) {
        guard let bundleIdentifier, let player = Self(rawValue: bundleIdentifier) else { return nil }
        self = player
    }

    var appName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Only Apple Music has a Favorite to change.
    var supportsFavorite: Bool { self == .music }

    /// Wrapped so a player that has quit isn't launched just to be asked.
    private func script(_ statement: String) -> String {
        "if application \"\(appName)\" is running then tell application \"\(appName)\" to \(statement)"
    }

    /// Play or pause, next, previous: sent to this app itself, not to whatever macOS thinks is playing.
    func transportScript(_ command: PlayerCommand) -> String { script(command.verb) }
    func seekScript(to seconds: TimeInterval) -> String { script("set player position to \(max(seconds, 0))") }

    var volumeScript: String { script("get sound volume") }
    func setVolumeScript(_ percent: Int) -> String { script("set sound volume to \(min(max(percent, 0), 100))") }
    var favoriteScript: String { script("get favorited of current track") }
    func setFavoriteScript(_ favorite: Bool) -> String { script("set favorited of current track to \(favorite)") }
}

/// What the player's transport buttons ask of the app.
enum PlayerCommand: Equatable {
    case playPause, next, previous

    /// The word Music and Spotify both understand.
    var verb: String {
        switch self {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
    }
}

/// Runs AppleScript off the main thread, since the first call may wait on a permission prompt.
enum PlayerScripting {
    static func volume(of player: ScriptablePlayer) async -> Int? {
        await run(player.volumeScript) { $0.descriptorType == DescType(typeNull) ? nil : Int($0.int32Value) }
    }

    static func setVolume(_ percent: Int, of player: ScriptablePlayer) {
        Task { _ = await run(player.setVolumeScript(percent)) { _ in true } }
    }

    /// Tells the player itself. `true` if it took the command, `false` if the script failed (say, no permission yet).
    static func send(_ command: PlayerCommand, to player: ScriptablePlayer) async -> Bool {
        await run(player.transportScript(command)) { _ in true } ?? false
    }

    static func seek(to seconds: TimeInterval, on player: ScriptablePlayer) async -> Bool {
        await run(player.seekScript(to: seconds)) { _ in true } ?? false
    }

    static func isFavorite(on player: ScriptablePlayer) async -> Bool? {
        await run(player.favoriteScript) { $0.descriptorType == DescType(typeNull) ? nil : $0.booleanValue }
    }

    static func setFavorite(_ favorite: Bool, on player: ScriptablePlayer) {
        Task { _ = await run(player.setFavoriteScript(favorite)) { _ in true } }
    }

    private static func run<T: Sendable>(
        _ source: String, _ extract: @escaping @Sendable (NSAppleEventDescriptor) -> T?
    ) async -> T? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result.flatMap(extract) : nil)
            }
        }
    }
}
