import Foundation
import Testing

@testable import MacIsland

@MainActor
struct FeatureCatalogTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MacIslandFeatures.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeSettings(_ defaults: UserDefaults? = nil) -> AppSettings {
        AppSettings(defaults: defaults ?? makeDefaults())
    }

    @Test func everyFeatureHasItsWords() {
        for feature in Feature.allCases {
            #expect(!feature.title.isEmpty && !feature.summary.isEmpty && !feature.systemImage.isEmpty, "\(feature)")
            #expect(!feature.cost.words.isEmpty, "\(feature)")
        }
        #expect(Set(Feature.allCases.map(\.title)).count == Feature.allCases.count, "titles are unique")
        // Stored, so renamed never: this list only grows.
        let stored = [
            "music", "clock", "reminders", "tools", "shelf", "clipboard", "notes", "agents", "calendar", "weather",
            "volumeHUD", "mixer", "system", "downloads", "chooseActivity", "notifications",
        ]
        #expect(stored.allSatisfy { Feature(rawValue: $0) != nil })
        #expect(Set(Feature.allCases.map(\.rawValue)) == Set(stored))
    }

    @Test func everyModuleButHomeHasAFeatureAndBackAgain() {
        for module in IslandModule.allCases where module != .home {
            #expect(Feature.module(for: module) != nil, "\(module)")
        }
        #expect(Feature.module(for: .home) == nil, "Home is always on")
        #expect(Feature.module(for: .media) == .music)
        for feature in Feature.allCases {
            if let module = feature.module { #expect(Feature.module(for: module) == feature) }
        }
    }

    @Test func aFreshInstallHasTodaysFeaturesOnAndTheNewOnesOff() {
        let settings = makeSettings()
        for feature in Feature.allCases {
            // Calendar is `showsCalendar`, which the guide turns on when Calendars is allowed: nothing asks at launch.
            let expected = feature.isOnByDefault && feature != .calendar
            #expect(settings.isOn(feature) == expected, "\(feature)")
        }
        #expect(Feature.allCases.filter(\.isNew).allSatisfy { !settings.isOn($0) })
        #expect(!settings.isOn(.volumeHUD), "off until turned on, as it always was")
        settings.showsCalendar = true
        #expect(settings.isOn(.calendar))
    }

    @Test func everydayIsTheDefault() {
        let settings = makeSettings()
        settings.showsCalendar = true  // what allowing Calendars in the guide does
        #expect(settings.matchingPreset() == .everyday)
        #expect(FeaturePreset.everyday.features == Set(Feature.allCases.filter { !$0.isNew && $0 != .volumeHUD }))
    }

    @Test func presetsSetExactlyTheirFeatures() {
        let settings = makeSettings()
        #expect(FeaturePreset.minimal.features == [.music, .clock, .shelf, .calendar])
        #expect(FeaturePreset.everything.features == Set(Feature.allCases))
        for preset in [FeaturePreset.minimal, .everything, .everyday, .minimal] {
            settings.apply(preset)
            for feature in Feature.allCases {
                #expect(settings.isOn(feature) == preset.features.contains(feature), "\(preset) \(feature)")
            }
            #expect(settings.matchingPreset() == preset)
        }
        settings.setOn(.tools, true)
        #expect(settings.matchingPreset() == nil, "one switch away from a preset is the person's own")
    }

    @Test func applyingAPresetChangesOnlyWhatFlips() {
        let settings = makeSettings()
        settings.apply(.everyday)
        var changed: [Feature] = []
        settings.onFeatureChange = { changed.append($0) }
        settings.apply(.minimal)
        #expect(Set(changed) == Set(FeaturePreset.everyday.features.subtracting(FeaturePreset.minimal.features)))
        #expect(changed.count == Set(changed).count, "one change per feature")
    }

    @Test func settingAFeatureToWhatItIsChangesNothing() {
        let defaults = makeDefaults()
        let settings = makeSettings(defaults)
        var changes = 0
        settings.onFeatureChange = { _ in changes += 1 }
        settings.setOn(.music, true)
        settings.setOn(.agents, false)
        settings.setOn(.calendar, false)
        settings.setOn(.volumeHUD, false)
        #expect(changes == 0)
        #expect(defaults.object(forKey: "features.available") == nil, "nothing is written for a no-op")
        settings.setOn(.music, false)
        settings.setOn(.music, false)
        #expect(changes == 1)
        #expect(AppSettings(defaults: defaults).isOn(.music) == false, "the choice is stored")
    }

    @Test func calendarIsShowsCalendarAndVolumeHUDIsReplacesVolumeHUD() {
        let settings = makeSettings()
        var changed: [Feature] = []
        settings.onFeatureChange = { changed.append($0) }

        settings.setOn(.calendar, true)
        #expect(settings.showsCalendar && settings.isOn(.calendar))
        settings.showsCalendar = false
        #expect(!settings.isOn(.calendar))
        settings.setOn(.volumeHUD, true)
        #expect(settings.replacesVolumeHUD && settings.isOn(.volumeHUD))
        settings.replacesVolumeHUD = false
        #expect(!settings.isOn(.volumeHUD))

        #expect(changed == [.calendar, .calendar, .volumeHUD, .volumeHUD], "every route says so, once")
        #expect(settings.featureChoices["calendar"] == nil && settings.featureChoices["volumeHUD"] == nil)

        // Assigning what it already is isn't a change.
        changed.removeAll()
        settings.showsCalendar = false
        settings.replacesVolumeHUD = false
        #expect(changed.isEmpty)
    }

    @Test func aClipboardTurnedOffBecomesTheClipboardFeatureOff() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "clipboardLimit")
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.isOn(.clipboard))
        #expect(settings.clipboardLimit == ClipboardHistory.limit)
        #expect(settings.effectiveClipboardLimit == 0, "the history stays off")

        // It was written, so the next launch reads the same.
        let again = AppSettings(defaults: defaults)
        #expect(!again.isOn(.clipboard) && again.clipboardLimit == ClipboardHistory.limit)
        #expect(defaults.integer(forKey: "clipboardLimit") == ClipboardHistory.limit)

        again.setOn(.clipboard, true)
        #expect(again.effectiveClipboardLimit == ClipboardHistory.limit)

        let kept = makeSettings()
        kept.clipboardLimit = 25
        #expect(kept.isOn(.clipboard) && kept.effectiveClipboardLimit == 25)
        kept.setOn(.clipboard, false)
        #expect(kept.clipboardLimit == 25, "the size is kept for when it is back on")
    }

    @Test func aModuleThatIsOffLeavesTheStripAndComesBackInItsPlace() {
        let viewModel = TestSupport.makeViewModel()
        let settings = viewModel.settings
        #expect(viewModel.visibleTabs() == IslandModule.defaultTabs)

        settings.setOn(.music, false)
        #expect(viewModel.visibleTabs() == [.home, .clock, .reminders, .tools])
        #expect(viewModel.leftTabs() == [.home, .clock, .reminders, .tools] && viewModel.rightTabs().isEmpty)
        #expect(settings.leftTabs == IslandModule.defaultTabs, "the stored strip never changes because of a switch")

        settings.setOn(.music, true)
        #expect(viewModel.visibleTabs() == IslandModule.defaultTabs)

        // On the right too.
        settings.move(.notes, to: .right)
        #expect(viewModel.rightTabs() == [.notes])
        settings.setOn(.notes, false)
        #expect(viewModel.rightTabs().isEmpty && settings.rightTabs == [.notes])
        settings.setOn(.notes, true)
        #expect(viewModel.rightTabs() == [.notes])
    }

    @Test func arrowKeysSkipAModuleThatIsOff() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.music, false)
        viewModel.select(.home)
        viewModel.selectAdjacentTab(1)
        #expect(viewModel.selectedTab == .clock)
    }

    @Test func theStripIsNeverEmpty() {
        let settings = makeSettings()
        settings.replaceTabs(left: [.media], right: [])
        settings.setOn(.music, false)
        #expect(settings.shownTabs == [.home] && settings.shownLeftTabs == [.home] && settings.shownRightTabs.isEmpty)

        settings.replaceTabs(left: [.media], right: [.notes])
        settings.setOn(.notes, false)
        #expect(settings.shownTabs == [.home])
        settings.setOn(.notes, true)
        #expect(settings.shownTabs == [.notes], "a shown tab on the right is a strip")
        #expect(settings.shownLeftTabs.isEmpty)

        // The last tab that shows can't be turned off.
        settings.replaceTabs(left: [.home, .media], right: [])
        settings.setOn(.music, false)
        settings.setEnabled(.home, false)
        #expect(settings.isInTabs(.home) && settings.shownTabs == [.home])
    }

    @Test func aModuleThatIsOffIsNotInTheMenuBarOrTheTray() {
        let settings = makeSettings()
        settings.setInMenuBar(.media, true)
        #expect(settings.showsInMenuBar(.media))

        settings.setOn(.music, false)
        #expect(!settings.showsInMenuBar(.media))
        #expect(settings.isInMenuBar(.media), "the choice is kept")
        #expect(!settings.hiddenModules.contains(.media), "it isn't in the tray either")
        #expect(!settings.isShown(.media) && settings.isShown(.home))

        // A module that is on and not in the strip is in the tray.
        #expect(settings.hiddenModules.contains(.shelf))
        settings.setOn(.shelf, false)
        #expect(!settings.hiddenModules.contains(.shelf))

        settings.setOn(.music, true)
        #expect(settings.showsInMenuBar(.media))
    }

    @Test func theMenuBarSetterIsStillANoOpWhenNothingChanges() {
        let settings = makeSettings()
        settings.setInMenuBar(.clock, true)
        let before = settings.menuBarModules
        settings.setInMenuBar(.clock, true)
        #expect(settings.menuBarModules == before)
    }

    @Test func turningOffTheSelectedTabGoesHome() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.onFeatureChange = { [weak viewModel] _ in viewModel?.leaveModuleThatIsOff() }
        viewModel.select(.media)
        viewModel.settings.setOn(.tools, false)
        #expect(viewModel.selectedTab == .media, "another module's switch leaves it be")
        viewModel.settings.setOn(.music, false)
        #expect(viewModel.selectedTab == .home)

        // A page that isn't in the strip goes home too.
        viewModel.select(.shelf)
        viewModel.settings.setOn(.shelf, false)
        #expect(viewModel.selectedTab == .home)
        viewModel.settings.setOn(.clipboard, false)
        #expect(viewModel.selectedTab == .home)
    }

    @Test func theURLRunnerOpensOnlyAModuleThatIsOn() {
        let viewModel = TestSupport.makeViewModel()
        let runner = URLCommandRunner(viewModel: viewModel)
        viewModel.settings.setOn(.music, false)
        runner.run(.open(.media))
        #expect(viewModel.selectedTab == .home)
        viewModel.settings.setOn(.music, true)
        runner.run(.open(.media))
        #expect(viewModel.selectedTab == .media)
    }

    @Test func theGuideFollowsTheModulesThatAreOn() {
        let suite = "MacIslandFeatures.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reference = TestSupport.makeViewModel()
        reference.settings.setOn(.music, false)
        reference.settings.setOn(.shelf, false)
        let model = OnboardingModel(
            state: OnboardingState(defaults: defaults, isExistingInstall: { false }), settings: reference.settings,
            geometry: { reference.geometry }, preview: IslandPreviewModel(live: reference.features),
            access: AccessModel(provider: StubAccess(), settings: reference.settings, onBluetoothAllowed: {}),
            replay: false, openSettings: {}, onEnd: { _ in })
        defer { model.stop() }
        #expect(!model.setup.tabs.contains(.media))
        #expect(!model.setup.hiddenModules.contains(.media) && !model.setup.hiddenModules.contains(.shelf))
        #expect(!model.shownModules.contains(.media) && !model.shownModules.contains(.shelf))
        #expect(model.shownModules.contains(.home) && model.shownModules.contains(.clock))
    }

    @Test func anArchiveCarriesFeaturesAndIgnoresUnknownOnes() throws {
        let original = makeSettings()
        original.setOn(.music, false)
        original.setOn(.agents, true)
        original.setOn(.calendar, true)
        var archive = SettingsArchive.make(from: original)
        #expect(archive.features?.count == Feature.allCases.count, "written in full")
        #expect(archive.features?["music"] == false && archive.features?["agents"] == true)

        archive.features?["teleporter"] = true  // a feature from a newer build
        let data = try archive.data()
        let target = makeSettings()
        target.restore(try SettingsArchive.read(data))
        #expect(!target.isOn(.music) && target.isOn(.agents) && target.isOn(.calendar) && target.isOn(.tools))
        #expect(target.featureChoices["teleporter"] == nil)

        // A file from before the catalog leaves the switches as they are.
        let before = target.featureChoices
        target.restore(try SettingsArchive.read(Data(#"{"format":"MacIsland Settings","version":2}"#.utf8)))
        #expect(target.featureChoices == before && !target.isOn(.music))
    }

    @Test func anArchiveWithAClipboardLimitOfZeroTurnsTheFeatureOff() {
        let settings = makeSettings()
        var archive = SettingsArchive()
        archive.clipboardLimit = 0
        settings.restore(archive)
        #expect(!settings.isOn(.clipboard) && settings.clipboardLimit == ClipboardHistory.limit)

        // A file that says both has its features win.
        var both = SettingsArchive()
        both.clipboardLimit = 0
        both.features = ["clipboard": true]
        settings.restore(both)
        #expect(settings.isOn(.clipboard))
    }

    @Test func resetAllTurnsTheDefaultsBackOn() {
        let settings = makeSettings()
        let fresh = makeSettings()
        settings.apply(.minimal)
        settings.setOn(.mixer, true)
        settings.setOn(.volumeHUD, true)
        settings.resetAll()
        for feature in Feature.allCases {
            #expect(settings.isOn(feature) == fresh.isOn(feature), "\(feature)")
        }
        #expect(settings.isOn(.tools) && settings.isOn(.notes) && !settings.isOn(.mixer))
    }

    // MARK: What a switch turns off (F2)

    /// Counts what the runner asked the app to start and stop.
    private final class Calls {
        var music: [Bool] = []
        var screenshots: [Bool] = []
    }

    private func makeRunner(_ viewModel: IslandViewModel, calls: Calls = Calls()) -> FeatureRunner {
        let runner = FeatureRunner(
            features: viewModel.features, viewModel: viewModel,
            music: { calls.music.append($0) }, screenshots: { calls.screenshots.append($0) })
        viewModel.settings.onFeatureChange = { runner.apply($0) }
        return runner
    }

    private func playing() -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "Song"
        state.artist = "Artist"
        state.isPlaying = true
        state.playbackRate = 1
        state.duration = 200
        state.timestamp = Date()
        return state
    }

    @Test func musicOffLeavesTheClosedIslandAndThePeek() {
        let viewModel = TestSupport.makeViewModel()
        _ = makeRunner(viewModel)
        viewModel.nowPlaying.apply(playing())
        #expect(viewModel.compactActivities == [.media])
        #expect(viewModel.peekContentHeight == viewModel.mediaContentHeight(peek: true))

        viewModel.settings.setOn(.music, false)
        #expect(viewModel.compactActivities.isEmpty && viewModel.compactActivity == .none)
        #expect(viewModel.peekContentHeight == Theme.Metrics.idlePeekHeight)

        viewModel.settings.setOn(.music, true)
        #expect(viewModel.compactActivities == [.media])
    }

    @Test func clockOffStopsARunningTimer() {
        let viewModel = TestSupport.makeViewModel()
        _ = makeRunner(viewModel)
        viewModel.timer.start(minutes: 5)
        viewModel.stopwatch.toggle()
        #expect(viewModel.compactActivities.contains(.timer))

        viewModel.settings.setOn(.clock, false)
        #expect(!viewModel.timer.isActive && !viewModel.stopwatch.isActive && !viewModel.pomodoro.isActive)
        #expect(viewModel.compactActivities.isEmpty)

        let runner = URLCommandRunner(viewModel: viewModel)
        runner.run(.timer(minutes: 5))
        runner.run(.stopwatch)
        runner.run(.pomodoro)
        #expect(!viewModel.timer.isActive && !viewModel.stopwatch.isActive && !viewModel.pomodoro.isActive)
    }

    @Test func shelfOffIgnoresADraggedFileAndTheShortcut() throws {
        let viewModel = TestSupport.makeViewModel()
        let calls = Calls()
        _ = makeRunner(viewModel, calls: calls)
        viewModel.settings.setOn(.shelf, false)
        #expect(viewModel.settings.effectiveDragTarget == .nothing)
        #expect(calls.screenshots == [false], "the screenshot search stops")

        viewModel.setFileDragActive(true)
        #expect(!viewModel.isFileDragActive)
        viewModel.setDropTargeted(true)
        #expect(viewModel.selectedTab != .shelf)
        viewModel.toggleShelfFromKeyboard()
        #expect(viewModel.state == .compact && viewModel.selectedTab != .shelf && !viewModel.isPinnedOpen)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        URLCommandRunner(viewModel: viewModel).run(.addToShelf(file))
        #expect(viewModel.shelf.items.isEmpty)

        viewModel.settings.setOn(.shelf, true)
        #expect(viewModel.settings.effectiveDragTarget == .shelfAndAirDrop)
        viewModel.toggleShelfFromKeyboard()
        #expect(viewModel.selectedTab == .shelf)
    }

    @Test func aWidgetWhoseFeatureIsOffGoesToAddWidgetsAndComesBack() {
        let settings = makeSettings()
        let music = WidgetID.builtIn(.music)
        let size = settings.homeLayout.widgets.first { $0.widget == music }?.size
        #expect(size != nil)

        settings.setOn(.music, false)
        #expect(!settings.homeLayout.isPlaced(music))
        #expect(settings.homeLayout.hidden.contains { $0.widget == music }, "kept, with its size")
        #expect(settings.homeHiddenByFeature == [music])
        #expect(!settings.isWidgetAllowed(music))

        settings.setOn(.music, true)
        #expect(settings.homeLayout.isPlaced(music))
        #expect(settings.homeLayout.widgets.first { $0.widget == music }?.size == size)
        #expect(settings.homeHiddenByFeature.isEmpty)

        // Today and Battery belong to no feature.
        #expect(WidgetCatalog.feature(of: .builtIn(.today)) == nil && WidgetCatalog.feature(of: .builtIn(.battery)) == nil)
        #expect(WidgetCatalog.feature(of: .builtIn(.clockActions)) == .clock)
    }

    @Test func aWidgetTheOwnerTookOffStaysOffWhenItsFeatureReturns() {
        let settings = makeSettings()
        let tools = WidgetID.builtIn(.quickTools)
        let id = settings.homeLayout.widgets.first { $0.widget == tools }!.id
        settings.setHomeLayout(settings.homeLayout.removing(id))
        settings.setOn(.tools, false)
        #expect(settings.homeHiddenByFeature.isEmpty, "it wasn\u{2019}t on Home to leave")
        settings.setOn(.tools, true)
        #expect(!settings.homeLayout.isPlaced(tools))
    }

    @Test func aWidgetComingBackToAFullHomeWaitsInAddWidgets() {
        let weather = WidgetID.builtIn(.weather)
        var full = HomeLayout(widgets: [
            WidgetPlacement(widget: .builtIn(.music), size: GridSize(6, 2)),
            WidgetPlacement(widget: .builtIn(.quickTools), size: GridSize(6, 1)),
        ])
        full.hidden = [WidgetPlacement(widget: weather, size: GridSize(1, 1))]
        #expect(full.capacityText() == "Home is full")
        let back = full.restoring([weather])
        #expect(back == full, "no room: it waits")
        #expect(!back.isPlaced(weather))

        // With room it returns at the size it had.
        let roomy = HomeLayout(
            widgets: [WidgetPlacement(widget: .builtIn(.today), size: GridSize(3, 1))],
            hidden: [WidgetPlacement(widget: weather, size: GridSize(2, 1))])
        let returned = roomy.restoring([weather])
        #expect(returned.widgets.first { $0.widget == weather }?.size == GridSize(2, 1))
    }

    @Test func homeIsNeverEmpty() {
        let settings = makeSettings()
        settings.setHomeLayout(HomeLayout(widgets: [WidgetPlacement(widget: .builtIn(.music), size: GridSize(3, 1))]))
        settings.setOn(.music, false)
        #expect(!settings.homeLayout.widgets.isEmpty)
        #expect(settings.homeLayout.isPlaced(.builtIn(.today)), "Today comes first")
        #expect(settings.homeHiddenByFeature == [.builtIn(.music)])

        // Everything that can leave, leaves.
        settings.apply(.minimal)
        settings.setOn(.music, false)
        settings.setOn(.clock, false)
        settings.setOn(.tools, false)
        #expect(!settings.homeLayout.widgets.isEmpty)
    }

    @Test func weatherOffKeepsTheCity() {
        let settings = makeSettings()
        settings.weatherCity = "Paris"
        #expect(FeatureRunner.weatherCity(settings) == "Paris")
        settings.setOn(.weather, false)
        #expect(FeatureRunner.weatherCity(settings) == "" && settings.weatherCity == "Paris")
        settings.setOn(.weather, true)
        #expect(FeatureRunner.weatherCity(settings) == "Paris")
    }

    @Test func clipboardOffStopsWatching() {
        let viewModel = TestSupport.makeViewModel()
        _ = makeRunner(viewModel)
        let clipboard = viewModel.clipboard
        defer { clipboard.stop() }
        clipboard.setCapacity(viewModel.settings.effectiveClipboardLimit)
        clipboard.record(.text("one"))
        #expect(clipboard.isWatching && clipboard.entries.count == 1)

        viewModel.settings.setOn(.clipboard, false)
        #expect(!clipboard.isWatching && clipboard.entries.isEmpty, "memory only, so it is forgotten")

        viewModel.settings.setOn(.clipboard, true)
        #expect(clipboard.isWatching && clipboard.capacity == viewModel.settings.clipboardLimit)

        // The Shelf has one mode without it.
        viewModel.setShelfMode(.clipboard)
        viewModel.settings.setOn(.clipboard, false)
        #expect(viewModel.shelfMode == .files)
        viewModel.setShelfMode(.clipboard)
        #expect(viewModel.shelfMode == .files, "the mode can\u{2019}t be chosen")
        viewModel.settings.setOn(.clipboard, true)
    }

    @Test func theAgendaStopsWhenBothSourcesAreOff() {
        let agenda = AgendaMonitor()
        defer { agenda.stop() }
        agenda.configure(calendar: true, reminders: false, mayAsk: false)
        #expect(agenda.isRefreshing)
        agenda.configure(calendar: false, reminders: false, mayAsk: false)
        #expect(!agenda.isRefreshing, "no 30 second timer with nothing to read")
    }

    @Test func theLaunchStartsOnlyWhatIsOn() {
        let on = TestSupport.makeViewModel()
        let onCalls = Calls()
        makeRunner(on, calls: onCalls).startAtLaunch()
        #expect(onCalls.music == [true] && onCalls.screenshots.isEmpty, "screenshots follow their own setting")

        let off = TestSupport.makeViewModel()
        off.settings.setOn(.music, false)
        let offCalls = Calls()
        makeRunner(off, calls: offCalls).startAtLaunch()
        #expect(offCalls.music.isEmpty, "the adapter is never started")

        // A change starts and stops it.
        let changing = TestSupport.makeViewModel()
        let calls = Calls()
        _ = makeRunner(changing, calls: calls)
        changing.settings.setOn(.music, false)
        changing.settings.setOn(.music, true)
        #expect(calls.music == [false, true])
    }

    @Test func notesOffLeavesNoPencilAndTheTabGoesHome() {
        let viewModel = TestSupport.makeViewModel()
        _ = makeRunner(viewModel)
        viewModel.select(.notes)
        viewModel.settings.setOn(.notes, false)
        #expect(viewModel.selectedTab == .home && !viewModel.showsStripPencil)
    }

    @Test func anEventWhoseFeatureIsOffSaysWhy() {
        let settings = makeSettings()
        func why(_ event: AmbientEvent) -> String? { NotificationsPane.requirement(for: event, settings: settings) }
        #expect(why(.meeting) == "Turn on Calendar in Features.")
        settings.setOn(.calendar, true)
        #expect(why(.meeting) == nil)

        settings.setOn(.reminders, false)
        #expect(why(.reminderDue) == "Turn on Reminders in Features.")
        settings.setOn(.reminders, true)
        #expect(why(.reminderDue) == "Turn on Due Reminders in Home.", "then the old note")
        settings.showsReminders = true
        #expect(why(.reminderDue) == nil)

        settings.setOn(.weather, false)
        #expect(why(.rainSoon) == "Turn on Weather in Features.")
        settings.setOn(.weather, true)
        #expect(why(.rainSoon) == "Set a city in Home.")
        settings.weatherCity = "Paris"
        #expect(why(.rainSoon) == nil)
        #expect(why(.charging) == nil)
    }

    // MARK: The Features pane (F3)

    @Test func everyBuiltFeatureHasASearchEntry() {
        for feature in Feature.allCases where feature.isBuilt {
            let found = SettingsSearch.results(for: feature.title)
            #expect(
                found.contains { $0.pane == .features && $0.anchor == SettingsAnchor.feature(feature) },
                "\(feature)")
        }
        // A feature that isn\u{2019}t built has no row, so nothing to find.
        #expect(!SettingsSearch.entries.contains { $0.pane == .features && $0.title == Feature.mixer.title })
        // The two switches that moved are found where they now are.
        #expect(SettingsSearch.results(for: "replace the volume hud").first?.pane == .features)
        #expect(SettingsSearch.results(for: "outlook").contains { $0.pane == .features && $0.title == "Calendar" })
        #expect(
            !SettingsSearch.entries.contains { $0.pane == .home && $0.title == "Calendar Events" }
                && !SettingsSearch.entries.contains { $0.pane == .notifications && $0.title == "Replace the Volume HUD" })
    }

    @Test func theFeaturesStopIsGroupedWithItsPane() {
        let ids = TourStop.all.map(\.id)
        #expect(ids.firstIndex(of: "features")! > ids.firstIndex(of: "input")!)
        #expect(ids.firstIndex(of: "features")! < ids.firstIndex(of: "tabs")!)
        let stop = TourStop.all.first { $0.id == "features" }
        #expect(stop?.pane == .features && stop?.scrollAnchor == SettingsAnchor.featurePresets)
        #expect(stop?.preview == nil)
    }

    @Test func aPresetSaysWhatItTurnsOn() {
        let minimal = FeaturePreset.minimal.confirmation
        for name in ["Music", "Clock", "Shelf", "Calendar"] { #expect(minimal.contains(name), "\(name)") }
        #expect(!minimal.contains("Tools") && minimal.contains("turns the rest off"))
        #expect(minimal.hasSuffix("Nothing is deleted: turning a feature back on brings its settings back."))
        #expect(FeaturePreset.everything.confirmation.hasPrefix("It turns every feature on."))
        #expect(FeaturePreset.everyday.confirmation.contains("Weather"))
    }

    @Test func turningOffSomethingLiveSaysWhatStops() {
        let viewModel = TestSupport.makeViewModel()
        let features = viewModel.features
        #expect(FeatureNotice.whatStops(.clock, features: features) == nil)
        features.timer.start(minutes: 5)
        #expect(FeatureNotice.whatStops(.clock, features: features) == "The running timer was stopped.")
        features.stopwatch.toggle()
        let both = FeatureNotice.whatStops(.clock, features: features) ?? ""
        #expect(both.contains("timer") && both.contains("stopwatch") && both.hasSuffix("were stopped."))
        features.timer.reset()
        features.stopwatch.reset()

        #expect(FeatureNotice.whatStops(.tools, features: features) == nil)

        features.clipboard.record(.text("copied"))
        #expect(FeatureNotice.whatStops(.clipboard, features: features) == "The clipboard history was cleared.")
        #expect(FeatureNotice.whatStops(.weather, features: features) == nil)
    }

    @Test func theFeatureCountIsOfTheFeaturesThisBuildHas() {
        let settings = makeSettings()
        let built = Feature.allCases.filter(\.isBuilt).count
        #expect(settings.featureCount.of == built)
        #expect(settings.featureCount.on == Feature.allCases.filter { $0.isBuilt && settings.isOn($0) }.count)
        settings.apply(.minimal)
        #expect(settings.featureCount.on == FeaturePreset.minimal.features.filter(\.isBuilt).count)
    }

    @Test func everyBuiltFeatureShowsWhereItLandsAndAnUnbuiltOneHasNoRow() {
        for feature in Feature.allCases where feature.isBuilt {
            #expect(feature.previewContext != nil, "\(feature)")
        }
        #expect(Feature.volumeHUD.previewContext?.showsVolume == true)
        #expect(Feature.calendar.previewContext?.event == .meeting)
        #expect(Feature.weather.previewContext?.presentation == .peek)
        #expect(Feature.shelf.previewContext?.fileDrag == true)
        #expect(!Feature.agents.isBuilt && !Feature.mixer.isBuilt)
    }

    @Test func anOffFeatureIsKeptApartFromItsSettings() {
        // Turning a feature off keeps what it was set to.
        let settings = makeSettings()
        settings.weatherCity = "Oslo"
        settings.clipboardLimit = 50
        settings.setOn(.weather, false)
        settings.setOn(.clipboard, false)
        settings.setOn(.weather, true)
        settings.setOn(.clipboard, true)
        #expect(settings.weatherCity == "Oslo" && settings.clipboardLimit == 50)
    }
}
