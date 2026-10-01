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
}
