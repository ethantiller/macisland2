import Carbon.HIToolbox
import Foundation
import Testing

@testable import MacIsland

@MainActor
struct OnboardingTests {
    private func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "MacIslandOnboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private let notesFile = URL(fileURLWithPath: "/tmp/MacIslandTests/notes.json")

    /// A state that classifies the way `InstallEvidence` would, but against a private suite and a pretend notes file.
    private func makeState(
        _ defaults: UserDefaults, notesExist: Bool = false, guideVersion: Int = OnboardingState.guideVersion
    ) -> OnboardingState {
        OnboardingState(
            defaults: defaults,
            isExistingInstall: {
                InstallEvidence.isExisting(defaults: defaults, notesFile: notesFile, fileExists: { _ in notesExist })
            },
            guideVersion: guideVersion)
    }

    // MARK: State

    @Test func freshInstallNeedsBoth() {
        let (defaults, _) = makeDefaults()
        let state = makeState(defaults)
        #expect(state.install == .fresh)
        #expect(state.needsGuide && state.needsTour)
        #expect(defaults.string(forKey: "onboarding.install") == "fresh")
    }

    @Test func updaterWithSettingsSkipsBoth() {
        let (defaults, _) = makeDefaults()
        defaults.set(["clock"], forKey: "tabsLeft")
        let state = makeState(defaults)
        #expect(state.install == .existing)
        #expect(!state.needsGuide && !state.needsTour)
        #expect(defaults.integer(forKey: "onboarding.guide") == 1)
        #expect(defaults.integer(forKey: "onboarding.settingsTour") == 1)
    }

    @Test func updaterWithOnlyTheNotesFileSkipsBoth() {
        let (defaults, _) = makeDefaults()
        let state = makeState(defaults, notesExist: true)
        #expect(state.install == .existing)
        #expect(!state.needsGuide && !state.needsTour)
    }

    @Test func classificationIsWrittenOnce() {
        let (defaults, _) = makeDefaults()
        _ = makeState(defaults)
        // The person quits mid-guide: a setting and the notes file now exist.
        defaults.set(["clock"], forKey: "tabsLeft")
        let again = makeState(defaults, notesExist: true)
        #expect(again.install == .fresh)
        #expect(again.needsGuide && again.needsTour)
    }

    @Test func finishingIsRemembered() {
        let (defaults, _) = makeDefaults()
        let state = makeState(defaults)
        state.finishGuide()
        state.finishTour()
        #expect(!state.needsGuide && !state.needsTour)
        let again = makeState(defaults)
        #expect(!again.needsGuide && !again.needsTour)
    }

    @Test func finishingTwiceDoesNotWriteAgain() {
        let (defaults, _) = makeDefaults()
        let state = makeState(defaults)
        state.finishGuide()
        defaults.removeObject(forKey: "onboarding.guide")
        state.finishGuide()
        #expect(defaults.object(forKey: "onboarding.guide") == nil)
    }

    @Test func aNewGuideVersionShowsAgain() {
        let (defaults, _) = makeDefaults()
        defaults.set(["clock"], forKey: "tabsLeft")
        let seen = makeState(defaults)
        #expect(!seen.needsGuide)
        let newer = makeState(defaults, guideVersion: 2)
        #expect(newer.needsGuide)
        #expect(!newer.needsTour)
        newer.finishGuide()
        #expect(!makeState(defaults, guideVersion: 2).needsGuide)
    }

    @Test func tourRequestIsInMemoryOnly() {
        let (defaults, _) = makeDefaults()
        let state = makeState(defaults)
        state.tourRequested = true
        #expect(!makeState(defaults).tourRequested)
    }

    #if DEBUG
        @Test func resetToFreshShowsBothAgain() {
            let (defaults, _) = makeDefaults()
            defaults.set(["clock"], forKey: "tabsLeft")
            let state = makeState(defaults)
            #expect(state.install == .existing)
            state.resetToFresh()
            #expect(state.install == .fresh)
            #expect(state.needsGuide && state.needsTour)
            // And it stays fresh on the next launch, whatever evidence is lying around.
            let again = makeState(defaults, notesExist: true)
            #expect(again.install == .fresh && again.needsGuide && again.needsTour)
        }
    #endif

    // MARK: Evidence

    /// The drift guard: every key `AppSettings` and the other stores write must be one `InstallEvidence` looks for, or an
    /// updater who only ever changed that setting would be shown the guide.
    @Test func evidenceKeysCoverEverySetting() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.setShortcut(.open, nil)
        settings.peeksOnHover = false
        settings.swipesEnabled = false
        settings.islandDisplay = .primary
        settings.move(.notes, to: .right)
        settings.setInMenuBar(.clock, true)
        settings.showsCalendar = true
        settings.showsReminders = true
        settings.weatherCity = "Paris"
        settings.dragTarget = .shelfOnly
        settings.addsScreenshots = false
        settings.shelfRetention = .week
        settings.clipboardLimit = 25
        settings.shelfMode = .clipboard
        settings.showsLyrics = false
        settings.showsMusicCompact = false
        settings.pinLimit = .eight
        settings.movePinned(settings.visiblePinned[4], before: settings.visiblePinned[0])
        settings.quietDuringFocus = true
        settings.fullChargeLevel = 90
        settings.setMuted(.hotspot, true)
        settings.saveCustomWidget(
            CustomWidget(
                title: "Stocks", systemImage: "chart.line.uptrend.xyaxis",
                source: .web(url: URL(string: "https://api.example.com/q")!, path: "p")))
        var layout = settings.homeLayout
        layout.widgets[1] = WidgetPlacement(widget: .custom(settings.customWidgets[0].id), size: GridSize(2, 1))
        settings.setHomeLayout(layout)
        _ = settings.saveHomePreset(named: "Mine")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.txt")
        try? Data("a".utf8).write(to: file)
        ShelfModel(defaults: defaults).add([file])

        let pomodoro = PomodoroModel(defaults: defaults)
        pomodoro.advance(completed: true)

        let written = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        #expect(!written.isEmpty)
        let missing = written.subtracting(InstallEvidence.keys)
        #expect(missing.isEmpty, "Add to InstallEvidence.keys: \(missing.sorted())")
    }

    @Test func anyEvidenceKeyMakesAnExistingInstall() {
        for key in InstallEvidence.keys {
            let (defaults, _) = makeDefaults()
            defaults.set("x", forKey: key)
            #expect(
                InstallEvidence.isExisting(defaults: defaults, notesFile: notesFile, fileExists: { _ in false }),
                "\(key)")
        }
    }

    @Test func otherKeysAreNotEvidence() {
        let (defaults, _) = makeDefaults()
        defaults.set(1, forKey: "NSStatusItem Preferred Position Item-0")
        defaults.set("/Users/me", forKey: "NSNavLastRootDirectory")
        #expect(!InstallEvidence.isExisting(defaults: defaults, notesFile: notesFile, fileExists: { _ in false }))
    }

    @Test func theNotesPathMatchesWhereNotesAreWritten() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        NotesModel(directory: folder).save()
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("notes.json").path))
        #expect(NotesModel.defaultFileURL.lastPathComponent == "notes.json")
        #expect(NotesModel.defaultFileURL.deletingLastPathComponent().lastPathComponent == "MacIsland")
    }

    // MARK: Settings file

    @Test func onboardingNeverEntersTheSettingsFile() throws {
        let (defaults, _) = makeDefaults()
        let state = makeState(defaults)
        state.finishGuide()
        state.finishTour()
        let settings = AppSettings(defaults: defaults)
        let text = String(decoding: try SettingsArchive.make(from: settings).data(), as: UTF8.self)
        #expect(!text.lowercased().contains("onboarding"))

        let before = ["onboarding.install", "onboarding.guide", "onboarding.settingsTour"].map {
            defaults.object(forKey: $0) as? NSObject
        }
        settings.resetAll()
        let after = ["onboarding.install", "onboarding.guide", "onboarding.settingsTour"].map {
            defaults.object(forKey: $0) as? NSObject
        }
        #expect(before == after)
    }
}

@MainActor
struct AccessTests {
    private func makeSettings() -> AppSettings {
        let suite = "MacIslandAccess.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    private func makeModel(
        _ stub: StubAccess, settings: AppSettings? = nil, onBluetoothAllowed: @escaping () -> Void = {}
    ) -> AccessModel {
        AccessModel(provider: stub, settings: settings ?? makeSettings(), onBluetoothAllowed: onBluetoothAllowed)
    }

    @Test func allowGrantsAndTurnsOnUpNext() async {
        let settings = makeSettings()
        let model = makeModel(StubAccess(), settings: settings)
        await model.allow(.calendars)
        #expect(model.state(of: .calendars) == .allowed)
        #expect(settings.showsCalendar && !settings.showsReminders)
        await model.allow(.reminders)
        #expect(settings.showsReminders)
    }

    @Test func denyLeavesUpNextOff() async {
        let settings = makeSettings()
        let model = makeModel(StubAccess(answers: [.calendars: false]), settings: settings)
        await model.allow(.calendars)
        #expect(model.state(of: .calendars) == .denied)
        #expect(!settings.showsCalendar)
    }

    @Test func aDecidedRowIsNotAskedAgain() async {
        let stub = StubAccess(states: [.calendars: .denied, .reminders: .allowed])
        let model = makeModel(stub)
        await model.allow(.calendars)
        await model.allow(.reminders)
        #expect(stub.requests.isEmpty)
    }

    @Test func skipAsksOnlyPendingInOrder() async {
        let stub = StubAccess(states: [.reminders: .allowed])
        let model = makeModel(stub)
        await model.requestAllPending()
        #expect(stub.requests == [.calendars, .bluetooth])
        #expect(model.asking == nil)
    }

    @Test func skipAsksNothingWhenAllDecided() async {
        let stub = StubAccess(states: [.calendars: .allowed, .reminders: .denied, .bluetooth: .allowed])
        await makeModel(stub).requestAllPending()
        #expect(stub.requests.isEmpty)
    }

    @Test func bluetoothGrantStartsTheMonitor() async {
        var started = 0
        let model = makeModel(StubAccess(), onBluetoothAllowed: { started += 1 })
        await model.allow(.bluetooth)
        #expect(started == 1)
        await model.allow(.bluetooth)
        #expect(started == 1)
    }

    @Test func bluetoothDenialDoesNotStartTheMonitor() async {
        var started = 0
        let model = makeModel(StubAccess(answers: [.bluetooth: false]), onBluetoothAllowed: { started += 1 })
        await model.allow(.bluetooth)
        #expect(started == 0)
    }

    @Test func allAllowedNeedsEveryRow() {
        #expect(!makeModel(StubAccess()).allAllowed)
        let all = StubAccess(states: [.calendars: .allowed, .reminders: .allowed, .bluetooth: .allowed])
        #expect(makeModel(all).allAllowed)
    }

    @Test func refreshReadsTheSystemAgain() {
        let stub = StubAccess()
        let model = makeModel(stub)
        stub.states[.calendars] = .allowed
        model.refresh()
        #expect(model.state(of: .calendars) == .allowed)
    }

    @Test func privacyAccessListsAccessibility() {
        let rows = PrivacyAccess.current()
        #expect(rows.contains { $0.id == "accessibility" })
        for kind in AccessKind.allCases { #expect(rows.contains { $0.id == kind.rawValue }) }
    }
}

struct KeyPartsTests {
    @Test func theDefaultShortcutIsControlOptionSpace() {
        let parts = KeyCombo.openDefault.parts
        #expect(parts.map(\.symbol) == ["\u{2303}", "\u{2325}", "Space"])
        #expect(parts.map(\.spoken) == ["Control", "Option", "Space"])
        #expect(KeyCombo.openDefault.display == "\u{2303}\u{2325}Space")
    }

    @Test func modifiersComeInMacOSOrder() {
        let combo = KeyCombo(keyCode: 40, modifiers: UInt32(cmdKey | shiftKey), label: "K")
        #expect(combo.parts.map(\.symbol) == ["\u{21E7}", "\u{2318}", "K"])
        #expect(combo.parts.map(\.spoken) == ["Shift", "Command", "K"])
        #expect(combo.display == "\u{21E7}\u{2318}K")
    }

    @Test func aFunctionKeyIsOnePart() {
        let combo = KeyCombo(keyCode: 96, modifiers: UInt32(controlKey), label: "F5")
        #expect(combo.parts.map(\.symbol) == ["\u{2303}", "F5"])
        #expect(combo.display == "\u{2303}F5")
    }

    @Test func arrowsAndEscapeAreReadByName() {
        #expect(KeyCombo.spoken("\u{2190}") == "Left Arrow")
        #expect(KeyCombo.spoken("\u{2192}") == "Right Arrow")
        #expect(KeyCombo.spoken("Esc") == "Escape")
        #expect(KeyCombo.spoken("Q") == "Q")
    }
}

@MainActor
struct LaunchPromptTests {
    private func makeState(existing: Bool) -> OnboardingState {
        let suite = "MacIslandLaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return OnboardingState(defaults: defaults, isExistingInstall: { existing })
    }

    @Test func aFreshInstallHoldsLaunchPromptsUntilTheGuideEnds() {
        let state = makeState(existing: false)
        #expect(state.holdsLaunchPrompts)
        state.finishGuide()
        #expect(!state.holdsLaunchPrompts)
    }

    @Test func anExistingInstallNeverHoldsThem() {
        #expect(!makeState(existing: true).holdsLaunchPrompts)
    }

    @Test func everyAccessKindHasItsWordsAndItsPane() {
        for kind in AccessKind.allCases {
            #expect(!kind.title.isEmpty && !kind.reason.isEmpty && !kind.symbol.isEmpty)
            #expect(kind.settingsURL != nil, "\(kind)")
        }
    }
}

struct GuideSearchTests {
    @Test func searchFindsTheGuideAndTheTour() {
        for query in ["tour", "onboarding", "tutorial", "welcome", "walkthrough"] {
            let found = SettingsSearch.results(for: query)
            #expect(found.contains { $0.anchor == SettingsAnchor.guide }, query)
        }
        let guide = SettingsSearch.results(for: "getting started").first
        #expect(guide?.title == "Welcome Guide" && guide?.pane == .general)
        #expect(SettingsSearch.results(for: "tips").first?.title == "Settings Tour")
    }
}
