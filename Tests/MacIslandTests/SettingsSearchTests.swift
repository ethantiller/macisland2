import Foundation
import Testing

@testable import MacIsland

/// Finding a setting by typing part of its name.
struct SettingsSearchTests {
    private func titles(_ query: String) -> [String] { SettingsSearch.results(for: query).map(\.title) }

    @Test func anEmptyQueryFindsNothing() {
        #expect(SettingsSearch.results(for: "").isEmpty)
        #expect(SettingsSearch.results(for: "   ").isEmpty)
    }

    @Test func everyPaneCanBeFoundByName() {
        for pane in SettingsPane.allCases {
            let found = SettingsSearch.results(for: pane.title)
            #expect(found.first?.pane == pane && found.first?.title == pane.title, "\(pane.title)")
        }
    }

    @Test func aTitleIsFoundByAnyPartOfItsWords() {
        #expect(titles("launch").first == "Launch at Login")
        #expect(titles("hover").first == "Peek on Hover")
        #expect(titles("lyr").first == "Synced Lyrics")
        #expect(titles("screenshots").first == "Add New Screenshots to the Shelf")
        #expect(titles("long break").first == "Long Break")
        #expect(Set(titles("pomodoro")) == ["Focus Length", "Short Break", "Long Break", "Sessions Before Long Break"])
    }

    @Test func anotherNameForASettingFindsIt() {
        #expect(titles("airpods").first == "Headphones")
        #expect(titles("startup").first == "Launch at Login")
        #expect(titles("hotkey").first == "Shortcut")
        #expect(titles("do not disturb").first == "Quiet in Focus")
        #expect(titles("umbrella").first == "Rain Soon")
    }

    @Test func everyWordHasToMatch() {
        #expect(titles("full charge").prefix(2).sorted() == ["Full Charge", "Full Charge Alert"])
        #expect(titles("full zebra").isEmpty)
        #expect(titles("zzzz").isEmpty)
    }

    @Test func accentsAndCaseDontMatter() {
        #expect(SettingsSearch.normalized("Café") == "cafe")
        #expect(titles("LAUNCH AT LOGIN").first == "Launch at Login")
    }

    @Test func aTitleBeatsAKeywordAndTiesKeepThePanesOrder() {
        // "calendar" is in Calendar Events' title and only a keyword for other entries.
        #expect(titles("calendar").first == "Calendar Events")
        let results = SettingsSearch.results(for: "reminders")
        let names = results.map { "\($0.pane.rawValue)/\($0.title)" }
        #expect(names.firstIndex(of: "home/Due Reminders")! < names.firstIndex(of: "notifications/Due Reminders")!)
    }

    @Test func everyEntryIsAUniquePlaceInARealPane() {
        let ids = SettingsSearch.entries.map(\.id)
        #expect(Set(ids).count == ids.count, "no entry twice")
        for entry in SettingsSearch.entries {
            #expect(entry.anchor.map { $0.hasPrefix(entry.pane.rawValue + ".") } ?? true, "\(entry.title)")
        }
    }

    @Test func searchFindsTheBannerSettingsThatChanged() {
        #expect(titles("low battery").first == "Low Battery")
        #expect(SettingsSearch.results(for: "low battery").first?.anchor == SettingsAnchor.power)
    }
}
