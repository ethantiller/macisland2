import AppKit
import Foundation
import Testing
@testable import MacIsland

@MainActor
struct PinnedToolsTests {
    private func makeSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "MacIslandPinTests")!
        defaults.removePersistentDomain(forName: "MacIslandPinTests")
        return AppSettings(defaults: defaults)
    }

    @Test func defaultsShowSixWithoutLowPower() {
        let settings = makeSettings()
        #expect(settings.visiblePinned.count == 6)
        #expect(!settings.isPinned(.lowPower))
    }

    @Test func pinningIntoAFullRowPushesOutTheOldest() {
        let settings = makeSettings()
        let oldest = settings.visiblePinned[0]
        settings.togglePin(.lowPower)
        #expect(settings.isPinned(.lowPower))
        #expect(!settings.isPinned(oldest))
        #expect(settings.visiblePinned.count == 6)
    }

    @Test func unpinningAndTheFourToolLimit() {
        let settings = makeSettings()
        settings.togglePin(.keepAwake)
        #expect(!settings.isPinned(.keepAwake))
        settings.pinLimit = .four
        #expect(settings.visiblePinned.count == 4)
    }

    @Test func pinsPersist() {
        let defaults = UserDefaults(suiteName: "MacIslandPinTests2")!
        defaults.removePersistentDomain(forName: "MacIslandPinTests2")
        let first = AppSettings(defaults: defaults)
        first.togglePin(.screenshot)
        #expect(!AppSettings(defaults: defaults).isPinned(.screenshot))
    }

    @Test func expandingToolsGrowsTheTab() {
        let viewModel = TestSupport.makeViewModel()
        let row = viewModel.contentHeight(for: .tools)
        viewModel.setToolsExpanded(true)
        #expect(viewModel.contentHeight(for: .tools) > row)
        viewModel.state = .expanded
        viewModel.state = .compact
        #expect(!viewModel.toolsExpanded)
    }
}

struct MeetingLinkTests {
    @Test func findsCallLinksInNotesAndLocation() {
        let zoom = MeetingLink.find(in: [nil, "Join: https://us02web.zoom.us/j/12345?pwd=abc. See you", nil])
        #expect(zoom?.absoluteString == "https://us02web.zoom.us/j/12345?pwd=abc")
        #expect(MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com")
        #expect(MeetingLink.find(in: ["Room 4B", "https://example.com/agenda"]) == nil)
    }
}

struct AgendaRulesTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func item(_ kind: AgendaItem.Kind, after seconds: TimeInterval) -> AgendaItem {
        AgendaItem(id: "\(kind)\(seconds)", kind: kind, title: "T", date: now.addingTimeInterval(seconds))
    }

    @Test func announcesEventsFiveMinutesAhead() {
        #expect(AgendaRules.shouldAnnounce(item(.event, after: 240), now: now))
        #expect(!AgendaRules.shouldAnnounce(item(.event, after: 900), now: now))
        #expect(!AgendaRules.shouldAnnounce(item(.event, after: -600), now: now))
    }

    @Test func announcesRecentlyDueRemindersOnly() {
        #expect(AgendaRules.shouldAnnounce(item(.reminder, after: -120), now: now))
        #expect(!AgendaRules.shouldAnnounce(item(.reminder, after: -7200), now: now))
        #expect(!AgendaRules.shouldAnnounce(item(.reminder, after: 1800), now: now))
    }

    @Test func picksTheSoonestAndDescribesIt() {
        let later = item(.event, after: 3000)
        let sooner = item(.reminder, after: 600)
        #expect(AgendaRules.next(in: [later, sooner]) == sooner)
        #expect(AgendaRules.next(in: []) == nil)
        #expect(AgendaRules.timeText(for: sooner, now: now) == "in 10 min")
        #expect(AgendaRules.timeText(for: item(.event, after: 10), now: now) == "Now")
        #expect(AgendaRules.timeText(for: item(.reminder, after: -600), now: now) == "Overdue")
    }
}

@MainActor
struct ClipboardHistoryTests {
    @Test func keepsNewestFirstWithoutRepeatsAndCapsAtTen() {
        let history = ClipboardHistory()
        history.record(.text("a"))
        history.record(.text("b"))
        history.record(.text("a"))
        let texts = history.entries.compactMap { entry -> String? in
            if case .text(let text) = entry.content { text } else { nil }
        }
        #expect(texts == ["a", "b"])

        for index in 0..<20 { history.record(.text("item \(index)")) }
        #expect(history.entries.count == ClipboardHistory.limit)
    }

    @Test func skipsConcealedCopiesAndDoesNotRerecordItsOwn() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacIslandTests.\(UUID().uuidString)"))
        let history = ClipboardHistory()

        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        history.poll(pasteboard: pasteboard)
        #expect(history.entries.isEmpty)

        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        history.poll(pasteboard: pasteboard)
        #expect(history.entries.count == 1)

        history.copy(history.entries[0], to: pasteboard)
        history.poll(pasteboard: pasteboard)
        #expect(history.entries.count == 1)
    }
}

@MainActor
struct FocusQuietTests {
    private func viewModel(quiet: Bool, focused: Bool) -> IslandViewModel {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.quietDuringFocus = quiet
        viewModel.focus.update(focused)
        return viewModel
    }

    private let banner = IslandBanner(systemImage: "bolt", tint: Theme.Tint.neutral, title: "T", detail: "D")

    @Test func quietHoldsBackAlertsAndBannersDuringFocus() {
        let viewModel = viewModel(quiet: true, focused: true)
        viewModel.flash(IslandAlert(systemImage: "bolt", tint: Theme.Tint.neutral, text: "82%"))
        #expect(viewModel.alert == nil)
        viewModel.showBanner(banner)
        #expect(viewModel.banner == nil)
    }

    @Test func alertsThatNeedAttentionStillArrive() {
        let viewModel = viewModel(quiet: true, focused: true)
        viewModel.showBanner(banner, followUp: IslandAlert(
            systemImage: "battery.25percent", tint: Theme.Tint.attention, text: "10%", staysUntilSeen: true
        ))
        #expect(viewModel.banner == nil && viewModel.alert?.text == "10%")
    }

    @Test func feedbackToYourOwnActionsIsNeverHeldBack() {
        let viewModel = viewModel(quiet: true, focused: true)
        viewModel.flash(IslandAlert(systemImage: "bolt", tint: Theme.Tint.neutral, text: "Copied"), respectingFocus: false)
        #expect(viewModel.alert?.text == "Copied")
    }

    @Test func offOrOutsideFocusShowsEverything() {
        let notQuiet = viewModel(quiet: false, focused: true)
        notQuiet.flash(IslandAlert(systemImage: "bolt", tint: Theme.Tint.neutral, text: "82%"))
        #expect(notQuiet.alert != nil)

        let notFocused = viewModel(quiet: true, focused: false)
        notFocused.showBanner(banner)
        #expect(notFocused.banner != nil)
    }
}

@MainActor
struct PinnedRowTests {
    private func makeSettings(limit: PinLimit) -> AppSettings {
        let defaults = UserDefaults(suiteName: "MacIslandPinnedRow")!
        defaults.removePersistentDomain(forName: "MacIslandPinnedRow")
        let settings = AppSettings(defaults: defaults)
        settings.pinLimit = limit
        return settings
    }

    @Test func unpinningNeverShortensTheRow() {
        let settings = makeSettings(limit: .four)
        for tool in settings.visiblePinned { settings.togglePin(tool) }
        #expect(settings.visiblePinned.count == 4)
        #expect(Set(settings.visiblePinned).count == 4)
    }

    @Test func unpinnedToolIsReplacedByAnotherOne() {
        let settings = makeSettings(limit: .four)
        let removed = settings.visiblePinned[0]
        settings.togglePin(removed)
        #expect(!settings.isPinned(removed))
        #expect(settings.visiblePinned.count == 4)
    }

    @Test func aShortListIsFilledToTheRowLength() {
        let settings = makeSettings(limit: .eight)
        #expect(AppSettings.filled([.muteMic], to: 8).count == min(8, ToolID.allCases.count))
        #expect(AppSettings.filled([.muteMic], to: 4).count == 4)
        #expect(AppSettings.filled([.muteMic], to: 4).first == .muteMic)
        // With eight slots and fewer tools, everything shows and pinning has nothing to change.
        #expect(settings.visiblePinned.count == min(8, ToolID.allCases.count))
        #expect(settings.rowShowsEveryTool == (ToolID.allCases.count <= 8))
    }

    @Test func aStoredShortListStillShowsAFullRow() {
        let defaults = UserDefaults(suiteName: "MacIslandPinnedRow2")!
        defaults.removePersistentDomain(forName: "MacIslandPinnedRow2")
        defaults.set([ToolID.focus.rawValue], forKey: "pinnedTools")
        defaults.set(6, forKey: "pinLimit")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.visiblePinned.count == 6)
        #expect(settings.visiblePinned.first == .focus)
    }
}

struct DropTileTests {
    @Test func tilesNeedBothAZoneAndAnActiveDrag() {
        #expect(ShelfView.showsDropTiles(zone: .shelf, isFileDragActive: true))
        #expect(!ShelfView.showsDropTiles(zone: .shelf, isFileDragActive: false))
        #expect(!ShelfView.showsDropTiles(zone: nil, isFileDragActive: true))
    }
}

@MainActor
struct MeetingAppTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func aTeamsLinkBecomesTheTeamsAppAddress() {
        let link = url("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%221%22%7d")
        #expect(MeetingLink.appURL(for: link)?.absoluteString
            == "msteams:/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%221%22%7d")
        #expect(MeetingLink.appURL(for: url("https://teams.microsoft.com/l/meeting/x"))?.scheme == "msteams")
        // Only the /l/ links have an app address.
        #expect(MeetingLink.appURL(for: url("https://teams.microsoft.com/other")) == nil)
        #expect(MeetingLink.appURL(for: url("https://teams.live.com/meet/123")) == nil)
    }

    @Test func aZoomLinkBecomesAZoomJoinAddress() {
        #expect(MeetingLink.appURL(for: url("https://us02web.zoom.us/j/12345678?pwd=abc123"))?.absoluteString
            == "zoommtg://zoom.us/join?confno=12345678&pwd=abc123")
        #expect(MeetingLink.appURL(for: url("https://zoom.us/j/999"))?.absoluteString == "zoommtg://zoom.us/join?confno=999")
        #expect(MeetingLink.appURL(for: url("https://zoom.us/j/notanumber")) == nil)
        #expect(MeetingLink.appURL(for: url("https://zoom.us/pricing")) == nil)
        #expect(MeetingLink.appURL(for: url("https://meet.google.com/abc-defg-hij")) == nil)
    }

    @Test func joinKeepsTheWebLinkWithoutTheApp() {
        let web = url("https://us02web.zoom.us/j/12345?pwd=x")
        #expect(MeetingLink.joinURL(for: web, hasHandler: { _ in false }) == web)
        #expect(MeetingLink.joinURL(for: web, hasHandler: { $0.scheme == "zoommtg" }).scheme == "zoommtg")
        let google = url("https://meet.google.com/abc-defg-hij")
        #expect(MeetingLink.joinURL(for: google, hasHandler: { _ in true }) == google)
    }

    @Test func safeLinksAreUnwrapped() {
        let wrapped = url("https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fabc%3Fx%3D1&data=05%7C01&sdata=zzz&reserved=0")
        #expect(MeetingLink.unwrap(wrapped).absoluteString == "https://teams.microsoft.com/l/meetup-join/abc?x=1")
        #expect(MeetingLink.find(in: ["Join \(wrapped.absoluteString) now"])?.host == "teams.microsoft.com")
    }

    @Test func googleRedirectsAreUnwrapped() {
        let redirect = url("https://www.google.com/url?q=https://meet.google.com/abc-defg-hij&sa=D&source=calendar")
        #expect(MeetingLink.unwrap(redirect).absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func otherLinksAreLeftAlone() {
        let plain = url("https://us02web.zoom.us/j/12345?pwd=abc")
        #expect(MeetingLink.unwrap(plain) == plain)
        let search = url("https://www.google.com/search?q=https://evil.example")
        #expect(MeetingLink.unwrap(search) == search)
        // An inner address that is not http(s) is not followed.
        let scripted = url("https://eur01.safelinks.protection.outlook.com/?url=file%3A%2F%2F%2Fetc%2Fpasswd")
        #expect(MeetingLink.unwrap(scripted) == scripted)
    }
}
