import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import MacIsland

@MainActor
struct ShortcutSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MacIslandShortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theDefaultsAreTheOldOnes() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.openShortcut == .openDefault)
        #expect(settings.openShortcut?.display == "\u{2303}\u{2325}Space")
    }

    @Test func theShelfHasItsOwnShortcutOnByDefault() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.shortcut(.shelf) == .shelfDefault)
        #expect(settings.shortcut(.shelf)?.display == "\u{2303}\u{2325}S")
        #expect(settings.setShortcut(.shelf, nil))
        #expect(AppSettings(defaults: defaults).shortcut(.shelf) == nil, "off is remembered")
        #expect(AppSettings(defaults: defaults).shortcut(.open) == .openDefault, "the island's own is untouched")
    }

    @Test func oneKeyCantOpenBothTheIslandAndTheShelf() {
        let settings = AppSettings(defaults: makeDefaults())
        var asked: [ShortcutSlot] = []
        settings.shortcutRegistrar = { slot, _ in
            asked.append(slot)
            return true
        }
        #expect(!settings.setShortcut(.shelf, .openDefault))
        #expect(settings.slot(holding: .openDefault, besides: .shelf) == .open)
        #expect(settings.shortcut(.shelf) == .shelfDefault)
        #expect(asked.isEmpty, "refused before the system is asked")
    }

    @Test func theOldPickerIsReadOnce() {
        let ctrlI = makeDefaults()
        ctrlI.set("controlOptionI", forKey: "hotkey")
        #expect(AppSettings(defaults: ctrlI).openShortcut == .controlOptionI)

        let off = makeDefaults()
        off.set("off", forKey: "hotkey")
        #expect(AppSettings(defaults: off).openShortcut == nil)

        // Once a new choice is stored it wins over the old key.
        let settings = AppSettings(defaults: ctrlI)
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | optionKey), label: "J")
        #expect(settings.setShortcut(.open, combo))
        #expect(AppSettings(defaults: ctrlI).openShortcut == combo)
    }

    @Test func offIsRememberedAndIsNotTheDefault() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.setShortcut(.open, nil))
        #expect(AppSettings(defaults: defaults).openShortcut == nil)
    }

    @Test func aShortcutNeedsControlOptionOrCommand() {
        let settings = AppSettings(defaults: makeDefaults())
        let bare = KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: 0, label: "J")
        let shiftOnly = KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(shiftKey), label: "J")
        #expect(!bare.isValid && !shiftOnly.isValid)
        #expect(!settings.setShortcut(.open, bare))
        #expect(!settings.setShortcut(.open, shiftOnly))
        #expect(settings.openShortcut == .openDefault)
        let command = KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey), label: "J")
        #expect(command.isValid && command.display == "\u{21E7}\u{2318}J")
    }

    @Test func aKeyAnotherAppOwnsIsRefusedAndTheOldOneStays() {
        let settings = AppSettings(defaults: makeDefaults())
        var asked: [KeyCombo?] = []
        settings.shortcutRegistrar = { _, combo in
            asked.append(combo)
            return false
        }
        let taken = KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey), label: "J")
        #expect(!settings.setShortcut(.open, taken))
        #expect(settings.openShortcut == .openDefault)
        #expect(asked == [taken])
        // The same value again asks nobody: nothing changed.
        #expect(settings.setShortcut(.open, .openDefault))
        #expect(asked.count == 1)
    }

    @Test func aRecordedKeyPressBecomesAComboOrSaysWhy() {
        #expect(RecorderOutcome.of(keyCode: UInt16(kVK_Escape), flags: [], characters: nil) == .cancelled)
        #expect(RecorderOutcome.of(keyCode: UInt16(kVK_Delete), flags: [], characters: nil) == .cleared)
        #expect(RecorderOutcome.of(keyCode: UInt16(kVK_ANSI_J), flags: [], characters: "j") == .needsModifier)
        #expect(RecorderOutcome.of(keyCode: UInt16(kVK_ANSI_J), flags: [.shift], characters: "J") == .needsModifier)
        #expect(
            RecorderOutcome.of(keyCode: UInt16(kVK_Space), flags: [.control, .option], characters: " ")
                == .combo(.openDefault))
        #expect(
            RecorderOutcome.of(keyCode: UInt16(kVK_ANSI_K), flags: [.control, .option], characters: "k")
                == .combo(KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey), label: "K")))
        // Esc with a modifier is a shortcut like any other.
        #expect(RecorderOutcome.of(keyCode: UInt16(kVK_Escape), flags: [.command], characters: nil) != .cancelled)
    }
}

@MainActor
struct InputSettingsTests {
    @Test func peekOnHoverOffOnlySwells() async throws {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.peeksOnHover = false
        viewModel.setHovering(true)
        #expect(viewModel.isSwelling)
        try await Task.sleep(for: .milliseconds(300))
        #expect(viewModel.state == .compact, "hover alone never opens the peek")
        viewModel.setHovering(false)
        #expect(!viewModel.isSwelling)
        // A click still opens it.
        viewModel.open()
        #expect(viewModel.state == .expanded)
    }

    @Test func inputChoicesPersist() {
        let viewModel = TestSupport.makeViewModel()
        let settings = viewModel.settings
        #expect(settings.peeksOnHover && settings.swipesEnabled && settings.islandDisplay == .builtIn)
        settings.swipesEnabled = false
        settings.islandDisplay = .primary
        #expect(!settings.swipesEnabled && settings.islandDisplay == .primary)
    }

    @Test func aDisplayChoiceIsTold() {
        let settings = TestSupport.makeViewModel().settings
        var told = 0
        settings.onDisplayChange = { told += 1 }
        settings.islandDisplay = .primary
        #expect(told == 1)
    }
}

struct DisplayChoiceTests {
    private typealias Traits = ScreenGeometry.Traits

    @Test func builtInPrefersTheNotchThenAnyBuiltInThenTheOneInUse() {
        let external = Traits(hasNotch: false, isBuiltIn: false)
        let notched = Traits(hasNotch: true, isBuiltIn: true)
        let builtInNoNotch = Traits(hasNotch: false, isBuiltIn: true)
        #expect(ScreenGeometry.choose([external, notched], preference: .builtIn) == 1)
        #expect(ScreenGeometry.choose([external, builtInNoNotch], preference: .builtIn) == 1)
        #expect(ScreenGeometry.choose([external, external], preference: .builtIn, mainIndex: 1) == 1)
        #expect(ScreenGeometry.choose([external, external], preference: .builtIn, mainIndex: 9) == 0)
    }

    @Test func primaryIsTheFirstScreen() {
        let external = Traits(hasNotch: false, isBuiltIn: false)
        let notched = Traits(hasNotch: true, isBuiltIn: true)
        #expect(ScreenGeometry.choose([external, notched], preference: .primary) == 0)
        #expect(ScreenGeometry.choose([], preference: .primary) == nil)
        #expect(ScreenGeometry.choose([], preference: .builtIn) == nil)
    }
}

@MainActor
struct NotificationSettingsTests {
    @Test func aMutedEventStaysSilentButFeedbackStillShows() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setMuted(.headphones, true)

        viewModel.showBanner(
            IslandBanner(systemImage: "airpods", tint: .white, title: "AirPods"), event: .headphones)
        #expect(viewModel.banner == nil, "muted")

        viewModel.showBanner(IslandBanner(systemImage: "airpods", tint: .white, title: "AirPods"), event: .drive)
        #expect(viewModel.banner != nil, "another event still shows")

        viewModel.flash(Announcements.hotspot, event: .hotspot)
        #expect(viewModel.alert != nil)
        viewModel.clearAlert()

        viewModel.settings.setMuted(.hotspot, true)
        viewModel.flash(Announcements.hotspot, event: .hotspot)
        #expect(viewModel.alert == nil)
        // What you just did is not an event, and always shows.
        viewModel.flash(IslandAlert(systemImage: "checkmark.circle.fill", tint: .green, text: "Copied"))
        #expect(viewModel.alert?.text == "Copied")
    }

    @Test func aMutedBannerDropsItsFollowUpToo() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setMuted(.lowBattery, true)
        let low = Announcements.lowBattery(percent: 15)
        viewModel.showBanner(low.banner, followUp: low.followUp, event: .lowBattery)
        #expect(viewModel.banner == nil && viewModel.alert == nil)
    }

    @Test func mutingPersistsAndDoesNothingWhenUnchanged() {
        let name = "MacIslandMute.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.mutedEvents.isEmpty)
        settings.setMuted(.rainSoon, true)
        settings.setMuted(.rainSoon, true)
        #expect(AppSettings(defaults: defaults).mutedEvents == [.rainSoon])
        settings.setMuted(.rainSoon, false)
        #expect(AppSettings(defaults: defaults).mutedEvents.isEmpty)
    }

    @Test func everyEventHasAGroupAndARealSample() {
        let viewModel = TestSupport.makeViewModel()
        for event in AmbientEvent.allCases {
            #expect(!event.title.isEmpty)
            switch Announcements.sample(for: event, agenda: viewModel.agenda) {
            case .banner(let banner): #expect(!banner.title.isEmpty, "\(event)")
            case .alert(let alert): #expect(!alert.text.isEmpty, "\(event)")
            }
        }
        #expect(Set(AmbientEvent.allCases.map(\.group)) == Set(AmbientEvent.Group.allCases))
        #expect(AmbientEvent.allCases.count == 12)
    }

    @Test func thePreviewDrawsAnEventsRealBannerOrAlert() {
        let live = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.show(PreviewContext(presentation: .banner, event: .headphones))
        #expect(preview.viewModel.banner?.title == "AirPods Pro")
        preview.show(PreviewContext(presentation: .banner, event: .hotspot))
        #expect(preview.viewModel.banner == nil)
        #expect(preview.viewModel.alert?.text == "Hotspot")
        preview.show(PreviewContext(presentation: .compact))
        #expect(preview.viewModel.alert == nil)
    }
}
