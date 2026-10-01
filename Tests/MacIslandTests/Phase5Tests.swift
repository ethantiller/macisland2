import CoreGraphics
import Foundation
import Observation
import Testing

@testable import MacIsland

// MARK: Shortcuts

struct ShortcutsCLITests {
    @Test func namesAreOnePerLineSortedWithoutBlanks() {
        let names = ShortcutsCLI.parse(listOutput: "Zebra\n\n  Apple  \nmango\n")
        #expect(names == ["Apple", "mango", "Zebra"])
        #expect(ShortcutsCLI.parse(listOutput: "").isEmpty)
    }
}

// MARK: Menu bar and windows

@MainActor
struct MenuBarAndWindowTests {
    @Test func nothingIsInTheMenuBarUntilChosenAndItPersists() {
        let defaults = UserDefaults(suiteName: "MacIslandMenuBar")!
        defaults.removePersistentDomain(forName: "MacIslandMenuBar")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.menuBarModules.isEmpty)
        settings.setInMenuBar(.media, true)
        settings.setInMenuBar(.media, true)
        #expect(settings.menuBarModules == [.media])
        #expect(AppSettings(defaults: defaults).isInMenuBar(.media))
        settings.setInMenuBar(.media, false)
        #expect(!settings.isInMenuBar(.media))
    }

    /// A menu-bar scene's binding writes the value it already reads. If that counted as a change, SwiftUI would
    /// update the scene, write again, and recurse until the app crashed.
    @Test func writingTheValueItAlreadyHasIsNotAChange() {
        let defaults = UserDefaults(suiteName: "MacIslandMenuBarNoop")!
        defaults.removePersistentDomain(forName: "MacIslandMenuBarNoop")
        let settings = AppSettings(defaults: defaults)
        var changes = 0
        func watch() {
            withObservationTracking {
                _ = settings.menuBarModules
            } onChange: {
                changes += 1
            }
        }
        watch()
        settings.setInMenuBar(.media, false)
        #expect(changes == 0)
        settings.setInMenuBar(.media, true)
        #expect(changes == 1)
        watch()
        settings.setInMenuBar(.media, true)
        #expect(changes == 1)
    }

    @Test func aTornOffWindowHasRoomForItsModule() {
        let viewModel = TestSupport.makeViewModel()
        for module in IslandModule.allCases where module.isAvailable {
            let size = FloatingPanels.initialSize(for: module, viewModel: viewModel)
            #expect(size.width == Theme.Metrics.detachedWidth + 2 * Theme.Metrics.floatPadding)
            #expect(size.height > viewModel.contentHeight(for: module))
        }
    }

    @Test func aTabsWindowRequestGoesToWhoeverOwnsTheWindows() {
        let viewModel = TestSupport.makeViewModel()
        var opened: IslandModule?
        viewModel.onOpenWindow = { opened = $0 }
        viewModel.openWindow(.tools)
        #expect(opened == .tools)
    }

    @Test func aWindowCanBeKeptOnTheDesktopAndBack() {
        let panel = FloatingGlassPanel()
        let normal = panel.level
        panel.keepsOnDesktop = true
        #expect(panel.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        #expect(panel.level.rawValue < normal.rawValue)
        panel.keepsOnDesktop = false
        #expect(panel.level == normal)
    }
}

// MARK: The music player

@MainActor
struct PlayerLayoutTests {
    private func playing() -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "willow"
        state.artist = "Taylor Swift"
        state.isPlaying = true
        state.duration = 214
        return state
    }

    @Test func theMediaTabHasBiggerArtAndSitsLowerThanThePeek() {
        #expect(Theme.Metrics.playerArtwork > Theme.Metrics.playerPeekArtwork)
        #expect(Theme.Metrics.playerTopInset > 0)
        let viewModel = TestSupport.makeViewModel()
        viewModel.nowPlaying.apply(playing())
        #expect(viewModel.mediaContentHeight(peek: false) > viewModel.mediaContentHeight(peek: true))
        #expect(viewModel.peekContentHeight == viewModel.mediaContentHeight(peek: true))
    }

    @Test func withNothingPlayingTheTabIsASingleLine() {
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.contentHeight(for: .media) == Theme.Metrics.glanceHeight)
    }

    @Test func thePlayerAndItsLyricFitBelowTheNotch() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.nowPlaying.apply(playing())
        let room =
            ScreenGeometry.panelSize.height - viewModel.geometry.notchSize.height - Theme.Metrics.contentTopGap
            - Theme.Metrics.margin
        // With a lyric line too, the tallest the player gets.
        let tallest = viewModel.mediaContentHeight(peek: false) + Theme.Metrics.lyricsRowHeight
        #expect(tallest <= room)
    }

    @Test func theTransportIsBigEnoughToHit() {
        #expect(Theme.Metrics.playerTransport >= Theme.Metrics.hitTarget)
    }
}

// MARK: Transport goes to the right app

@MainActor
struct TransportRoutingTests {
    private func track(bundle: String?) -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "willow"
        state.artist = "Taylor Swift"
        state.isPlaying = true
        state.bundleIdentifier = bundle
        return state
    }

    /// Runs a transport action and returns what was sent to a player, waiting for the task the model starts.
    private func sent(bundle: String?, _ action: (NowPlayingModel) -> Void) async -> [(PlayerCommand, ScriptablePlayer)]
    {
        let model = NowPlayingModel(adapter: nil)
        var received: [(PlayerCommand, ScriptablePlayer)] = []
        model.sendToPlayer = { command, player in
            received.append((command, player))
            return true
        }
        model.apply(track(bundle: bundle))
        action(model)
        try? await Task.sleep(for: .milliseconds(50))
        return received
    }

    @Test func aMusicPauseGoesToMusicItselfNotToWhateverIsPlaying() async {
        let received = await sent(bundle: "com.apple.Music") { $0.togglePlayPause() }
        #expect(received.count == 1)
        #expect(received.first?.0 == .playPause && received.first?.1 == .music)
    }

    @Test func spotifyGetsAllThreeCommands() async {
        var commands: [PlayerCommand] = []
        let model = NowPlayingModel(adapter: nil)
        model.sendToPlayer = { command, player in
            #expect(player == .spotify)
            commands.append(command)
            return true
        }
        model.apply(track(bundle: "com.spotify.client"))
        model.togglePlayPause()
        model.nextTrack()
        model.previousTrack()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(commands == [.playPause, .next, .previous])
    }

    @Test func otherAppsStillUseTheSystemsCommand() async {
        #expect(await sent(bundle: "com.google.Chrome") { $0.togglePlayPause() }.isEmpty)
        #expect(await sent(bundle: nil) { $0.nextTrack() }.isEmpty)
    }

    @Test func theButtonStillShowsTheChangeAtOnce() async {
        let model = NowPlayingModel(adapter: nil)
        model.sendToPlayer = { _, _ in true }
        model.apply(track(bundle: "com.apple.Music"))
        model.togglePlayPause()
        #expect(!model.state.isPlaying)
    }

    @Test func theScriptsNameTheAppAndOnlyTouchItWhileItRuns() {
        let script = ScriptablePlayer.music.transportScript(.playPause)
        #expect(script == #"if application "Music" is running then tell application "Music" to playpause"#)
        #expect(ScriptablePlayer.spotify.transportScript(.next).hasSuffix("next track"))
        #expect(ScriptablePlayer.spotify.transportScript(.previous).hasSuffix("previous track"))
        #expect(ScriptablePlayer.music.seekScript(to: 42).hasSuffix("set player position to 42.0"))
        #expect(ScriptablePlayer.music.seekScript(to: -5).hasSuffix("set player position to 0.0"))
    }
}
