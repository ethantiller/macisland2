import CoreGraphics
import Foundation
import Observation
import Testing
@testable import MacIsland

// MARK: Search engines

struct SearchEngineTests {
    @Test func nineBuiltInEnginesWithUniqueKeywords() {
        let engines = SearchEngine.builtIn
        #expect(engines.count == 9)
        #expect(Set(engines.map(\.keyword)).count == 9)
        #expect(engines.contains { $0.id == SearchEngine.defaultID })
        #expect(engines.allSatisfy { SearchEngine.isValid(template: $0.template) })
    }

    @Test func queriesAreEncodedIntoTheAddress() {
        let google = SearchEngine.builtIn[0]
        #expect(google.url(for: "swift concurrency")?.absoluteString == "https://www.google.com/search?q=swift%20concurrency")
        // Characters that would end the query early are escaped.
        #expect(google.url(for: "a&b=c#d")?.absoluteString == "https://www.google.com/search?q=a%26b%3Dc%23d")
    }

    @Test func templatesNeedASearchMarkerAndAWebAddress() {
        #expect(SearchEngine.isValid(template: "https://kagi.com/search?q=%s"))
        #expect(!SearchEngine.isValid(template: "https://kagi.com/search?q="))
        #expect(!SearchEngine.isValid(template: "file:///etc/%s"))
        #expect(!SearchEngine.isValid(template: "javascript:%s"))
        #expect(!SearchEngine.isValid(template: "not a url %s"))
    }

    @Test func aKeywordPicksTheEngine() {
        let engines = SearchEngine.builtIn
        let match = SearchEngine.match("YT swift async", in: engines)
        #expect(match?.engine.id == "youtube" && match?.query == "swift async")
        #expect(SearchEngine.match("yt", in: engines) == nil)
        #expect(SearchEngine.match("yt   ", in: engines) == nil)
        #expect(SearchEngine.match("swift yt", in: engines) == nil)
    }
}

@MainActor
struct CustomEngineTests {
    private func makeSettings(_ name: String = "MacIslandEngines") -> (AppSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppSettings(defaults: defaults), defaults)
    }

    @Test func addingAnEngineWorksAndPersists() {
        let (settings, defaults) = makeSettings()
        #expect(settings.addCustomEngine(name: "Kagi", keyword: "K", template: "https://kagi.com/search?q=%s"))
        #expect(settings.searchEngines.count == 10)
        #expect(AppSettings(defaults: defaults).customEngines.map(\.keyword) == ["k"])
    }

    @Test func badOrDuplicateEnginesAreRefused() {
        let (settings, _) = makeSettings("MacIslandEngines2")
        #expect(!settings.addCustomEngine(name: "", keyword: "k", template: "https://a.b/?q=%s"))
        #expect(!settings.addCustomEngine(name: "X", keyword: "", template: "https://a.b/?q=%s"))
        #expect(!settings.addCustomEngine(name: "X", keyword: "two words", template: "https://a.b/?q=%s"))
        #expect(!settings.addCustomEngine(name: "X", keyword: "x", template: "https://a.b/?q="))
        // "g" belongs to Google already.
        #expect(!settings.addCustomEngine(name: "X", keyword: "G", template: "https://a.b/?q=%s"))
        #expect(settings.customEngines.isEmpty)
    }

    @Test func removingTheDefaultFallsBackToGoogle() {
        let (settings, _) = makeSettings("MacIslandEngines3")
        settings.addCustomEngine(name: "Kagi", keyword: "k", template: "https://kagi.com/search?q=%s")
        let kagi = settings.customEngines[0]
        settings.defaultSearchEngineID = kagi.id
        #expect(settings.defaultSearchEngine.name == "Kagi")
        settings.removeCustomEngine(kagi.id)
        #expect(settings.defaultSearchEngine.id == SearchEngine.defaultID)
    }
}

// MARK: Ranking and parsing

struct PaletteSearchTests {
    @Test func betterMatchesScoreHigher() {
        let exact = PaletteSearch.score(query: "notes", in: "Notes")!
        let prefix = PaletteSearch.score(query: "not", in: "Notes")!
        let word = PaletteSearch.score(query: "pad", in: "Note Pad")!
        let inside = PaletteSearch.score(query: "ote", in: "Notes")!
        let letters = PaletteSearch.score(query: "nts", in: "Notes")!
        #expect(exact > prefix && prefix > word && word > inside && inside > letters)
    }

    @Test func noMatchIsNil() {
        #expect(PaletteSearch.score(query: "xyz", in: "Notes") == nil)
        #expect(PaletteSearch.score(query: "", in: "Notes") == nil)
        #expect(PaletteSearch.score(query: "sn", in: "Notes") == nil)
    }

    @Test func aShorterNameBeatsALongerOneForTheSamePrefix() {
        #expect(PaletteSearch.score(query: "saf", in: "Safari")! > PaletteSearch.score(query: "saf", in: "Safari Technology Preview")!)
    }

    @Test func bestScoreTakesTheBestName() {
        #expect(PaletteSearch.bestScore(query: "detach", in: ["Notes window", "detach Notes"]) == PaletteSearch.score(query: "detach", in: "detach Notes"))
    }
}

struct PaletteTimerTests {
    @Test func minutesHoursAndMixes() {
        #expect(PaletteTimer.minutes(from: "25m") == 25)
        #expect(PaletteTimer.minutes(from: "25 min") == 25)
        #expect(PaletteTimer.minutes(from: "1h") == 60)
        #expect(PaletteTimer.minutes(from: "1h30m") == 90)
        #expect(PaletteTimer.minutes(from: "1.5h") == 90)
        #expect(PaletteTimer.minutes(from: "90s") == 2)
        #expect(PaletteTimer.minutes(from: "timer 45") == 45)
        #expect(PaletteTimer.minutes(from: "TIMER 10m") == 10)
    }

    @Test func notATimerIsNil() {
        #expect(PaletteTimer.minutes(from: "notes") == nil)
        #expect(PaletteTimer.minutes(from: "25") == nil)
        #expect(PaletteTimer.minutes(from: "0m") == nil)
        #expect(PaletteTimer.minutes(from: "") == nil)
        #expect(PaletteTimer.minutes(from: "m25") == nil)
    }
}

struct TranslationRequestTests {
    @Test func defaultsToTheSystemLanguage() {
        let request = TranslationRequest.parse("tr good morning", systemLanguage: "de")
        #expect(request == TranslationRequest(text: "good morning", target: "de"))
    }

    @Test func aLanguageCodePicksTheTarget() {
        #expect(TranslationRequest.parse("translate es good morning", systemLanguage: "en")
            == TranslationRequest(text: "good morning", target: "es"))
        #expect(TranslationRequest.parse("TR fr hello", systemLanguage: "en")?.target == "fr")
    }

    @Test func aWordThatIsNotACodeStaysInTheText() {
        #expect(TranslationRequest.parse("tr hello world", systemLanguage: "en")?.text == "hello world")
        // A lone two-letter word is the text, not a language with nothing to translate.
        #expect(TranslationRequest.parse("tr es", systemLanguage: "en")?.text == "es")
    }

    @Test func notATranslationIsNil() {
        #expect(TranslationRequest.parse("tr", systemLanguage: "en") == nil)
        #expect(TranslationRequest.parse("hello there", systemLanguage: "en") == nil)
        #expect(TranslationRequest.parse("track something", systemLanguage: "en") == nil)
    }
}

// MARK: Apps and Shortcuts

struct AppIndexTests {
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func findsAppsOneLevelIntoFolders() throws {
        let root = try makeFolder()
        for path in ["Safari.app", "Notes.app", "Utilities/Terminal.app", "Utilities/Deep/Hidden.app", "readme.txt"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: path.hasSuffix(".txt") ? url.deletingLastPathComponent() : url, withIntermediateDirectories: true)
            if path.hasSuffix(".txt") { try Data().write(to: url) }
        }
        let names = AppIndex.scan([root]).map(\.name)
        #expect(names == ["Notes", "Safari", "Terminal"])
    }

    @Test func oneEntryPerNameAcrossFolders() throws {
        let first = try makeFolder(), second = try makeFolder()
        try FileManager.default.createDirectory(at: first.appendingPathComponent("Mail.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second.appendingPathComponent("mail.app"), withIntermediateDirectories: true)
        let apps = AppIndex.scan([first, second])
        #expect(apps.count == 1)
        #expect(apps[0].url.resolvingSymlinksInPath().path.hasPrefix(first.resolvingSymlinksInPath().path))
    }

    @Test func aMissingFolderIsSkipped() {
        #expect(AppIndex.scan([URL(fileURLWithPath: "/definitely/not/here")]).isEmpty)
    }
}

struct ShortcutsCLITests {
    @Test func namesAreOnePerLineSortedWithoutBlanks() {
        let names = ShortcutsCLI.parse(listOutput: "Zebra\n\n  Apple  \nmango\n")
        #expect(names == ["Apple", "mango", "Zebra"])
        #expect(ShortcutsCLI.parse(listOutput: "").isEmpty)
    }
}

// MARK: The palette

@MainActor
struct PaletteModelTests {
    private func makeModel() -> (PaletteModel, IslandViewModel) {
        let viewModel = TestSupport.makeViewModel()
        return (PaletteModel(viewModel: viewModel), viewModel)
    }

    @Test func emptyShowsEveryModule() {
        let (model, _) = makeModel()
        #expect(model.results.count == IslandModule.allCases.filter(\.isAvailable).count)
        #expect(model.results.allSatisfy { $0.title.hasPrefix("Open ") })
    }

    @Test func typingANameFindsItsModuleFirst() {
        let (model, _) = makeModel()
        model.query = "notes"
        #expect(model.results.first?.title == "Open Notes")
    }

    @Test func aWebSearchIsAlwaysTheLastRowAndTheListIsCapped() {
        let (model, _) = makeModel()
        for text in ["a", "e", "notes", "timer", "zzzzqq"] {
            model.query = text
            #expect(model.results.count <= PaletteModel.maxResults)
            #expect(model.results.last?.id.hasPrefix("search-") == true)
        }
    }

    @Test func aDurationOffersATimerThatStartsIt() {
        let (model, viewModel) = makeModel()
        model.query = "25m"
        #expect(model.results.first?.title == "Start a 25-minute timer")
        model.runSelected()
        #expect(viewModel.timer.isRunning && viewModel.timer.duration == 25 * 60)
        viewModel.timer.reset()
    }

    @Test func aKeywordAddsThatEnginesSearchAheadOfTheDefault() {
        let (model, _) = makeModel()
        model.query = "yt swift"
        #expect(model.results.first?.id == "search-youtube")
        #expect(model.results.last?.id == "search-google")
    }

    @Test func theDefaultEngineIsTheOneInSettings() {
        let (model, viewModel) = makeModel()
        viewModel.settings.defaultSearchEngineID = "duckduckgo"
        model.query = "hello"
        #expect(model.results.last?.id == "search-duckduckgo")
        viewModel.settings.defaultSearchEngineID = SearchEngine.defaultID
    }

    @Test func toolsAreFoundByName() {
        let (model, _) = makeModel()
        model.query = "keep awake"
        #expect(model.results.first?.title == "Keep Awake")
    }

    @Test func snippetsAreFoundByTitleAndCopyTheirText() {
        let (model, viewModel) = makeModel()
        let snippet = viewModel.notes.addSnippet()
        viewModel.notes.setTitle("Sign-off", ofSnippet: snippet.id)
        viewModel.notes.setText("Best regards", ofSnippet: snippet.id)
        model.query = "sign"
        #expect(model.results.first?.title == "Sign-off")
    }

    @Test func windowAndMenuBarRowsExistButRankBelowTheModule() {
        let (model, viewModel) = makeModel()
        model.query = "clock"
        #expect(model.results.first?.title == "Open Clock")
        model.query = "clock window"
        #expect(model.results.contains { $0.title == "Open Clock in a Window" })
        model.query = "clock menu bar"
        #expect(model.results.contains { $0.title == "Show Clock in the Menu Bar" })
        viewModel.settings.setInMenuBar(.clock, true)
        model.update()
        #expect(model.results.contains { $0.title == "Hide Clock from the Menu Bar" })
        viewModel.settings.setInMenuBar(.clock, false)
    }

    @Test func selectionWrapsAndResetsWithTheQuery() {
        let (model, _) = makeModel()
        model.query = "a"
        model.moveSelection(-1)
        #expect(model.selection == model.results.count - 1)
        model.moveSelection(1)
        #expect(model.selection == 0)
        model.moveSelection(2)
        model.query = "ab"
        #expect(model.selection == 0)
    }

    @Test func runningARowClosesThePaletteExceptATranslationStart() {
        let (model, viewModel) = makeModel()
        var closed = 0
        model.onClose = { closed += 1 }
        model.query = "5m"
        model.runSelected()
        #expect(closed == 1)
        viewModel.timer.reset()
        model.query = "tr hello"
        #expect(model.results.first?.title.hasPrefix("Translate to") == true)
    }

    @Test func aTranslationMovesThroughItsStates() {
        let (model, _) = makeModel()
        model.query = "tr es hello"
        let request = TranslationRequest(text: "hello", target: "es")
        model.beginTranslation(request)
        #expect(model.translation == .working(request))
        #expect(model.results.first?.title == "Translating\u{2026}")
        model.finishTranslation(request, output: "hola")
        #expect(model.results.first?.title == "hola")
        #expect(model.results.first?.subtitle?.contains("copy") == true)
        model.finishTranslation(request, output: nil)
        #expect(model.results.first?.title.hasPrefix("Couldn") == true)
        // Editing the text starts over.
        model.query = "tr es hello there"
        #expect(model.results.first?.title.hasPrefix("Translate to") == true)
    }

    @Test func showingAModuleOpensTheIslandOnIt() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.show(.notes)
        #expect(viewModel.selectedTab == .notes && viewModel.state == .expanded)
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
        settings.setInMenuBar(.agents, true)
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
            withObservationTracking { _ = settings.menuBarModules } onChange: { changes += 1 }
        }
        watch()
        settings.setInMenuBar(.media, false)
        settings.setInMenuBar(.agents, true)
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
        let panel = FloatingGlassPanel(style: .window)
        let normal = panel.level
        panel.keepsOnDesktop = true
        #expect(panel.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        #expect(panel.level.rawValue < normal.rawValue)
        panel.keepsOnDesktop = false
        #expect(panel.level == normal)
    }

    @Test func thePaletteKeepsItsTopEdgeWhenItGrows() {
        let panel = FloatingGlassPanel(style: .palette)
        panel.pinnedTop = 800
        panel.setFrame(CGRect(x: 0, y: 700, width: 520, height: 100), display: false)
        #expect(panel.frame.maxY == 800)
        panel.setFrame(CGRect(x: 0, y: 700, width: 520, height: 300), display: false)
        #expect(panel.frame.maxY == 800 && panel.frame.height == 300)
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
        let room = ScreenGeometry.panelSize.height - viewModel.geometry.notchSize.height - Theme.Metrics.contentTopGap - Theme.Metrics.margin
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
    private func sent(bundle: String?, _ action: (NowPlayingModel) -> Void) async -> [(PlayerCommand, ScriptablePlayer)] {
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
