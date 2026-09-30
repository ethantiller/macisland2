import Foundation
import Testing
@testable import MacIsland

@MainActor
struct SettingsTests {
    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MacIslandSettingsTests")!
        defaults.removePersistentDomain(forName: "MacIslandSettingsTests")
        return defaults
    }

    @Test func hotkeyChoicePersistsAndNotifies() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.hotkey == .controlOptionSpace)

        var notified: HotkeyChoice?
        settings.onHotkeyChange = { notified = $0 }
        settings.hotkey = .off
        #expect(notified == .off)
        #expect(AppSettings(defaults: defaults).hotkey == .off)
    }

    @Test func offHasNoKeyCombo() {
        #expect(HotkeyChoice.off.keyCombo == nil)
        #expect(HotkeyChoice.controlOptionSpace.keyCombo != nil)
    }

    @Test func tabsDefaultToFiveAndPersist() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.tabs == [.home, .media, .clock, .reminders, .tools])

        settings.toggleTab(.clock)
        #expect(!settings.tabs.contains(.clock))
        #expect(AppSettings(defaults: defaults).tabs == settings.tabs)
    }

    @Test func tabsStayBetweenOneAndMax() {
        let settings = AppSettings(defaults: makeDefaults())
        for module in IslandModule.allCases where module.isAvailable { settings.toggleTab(module) }
        #expect(settings.tabs.count >= 1)
        #expect(settings.tabs.count <= Theme.Metrics.maxTabs + Theme.Metrics.maxRightTabs)

        // Unavailable modules can't be added, and a full strip refuses another.
        let full = AppSettings(defaults: makeDefaults())
        full.toggleTab(.agents)
        #expect(full.tabs == IslandModule.defaultTabs)
        #expect(AppSettings.normalized([]) == IslandModule.defaultTabs)
    }

    @Test func viewModelReadsTabsFromSettings() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.toggleTab(.clock)
        #expect(viewModel.visibleTabs() == viewModel.settings.tabs)
        #expect(!viewModel.visibleTabs().contains(.clock))
    }
}
