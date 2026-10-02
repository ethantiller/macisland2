import Foundation
import Testing

@testable import MacIsland

/// What a notification does on the island: where it shows, what is closed, and what the widget lists.
@MainActor
struct NotificationMirrorTests {
    private static let closeAction = "Name:Close\nTarget:0x0\nSelector:(null)"

    @MainActor private struct Rig {
        let viewModel: IslandViewModel
        let mac: FixtureMac
        var mirror: NotificationMirror { viewModel.features.notifications }
    }

    /// A Mac whose Notification Center is read, behind a view model whose Notifications feature uses it. Started, and past the first scan.
    private func rig(placement: NotificationPlacement = .island) async -> Rig {
        let mac = FixtureMac()
        let viewModel = TestSupport.makeViewModel(notifications: { settings in
            NotificationMirror(reader: mac.reader(), placement: { settings.notificationPlacement })
        })
        viewModel.settings.notificationPlacement = placement
        viewModel.features.notifications.connect(to: viewModel)
        viewModel.features.notifications.start()
        await viewModel.features.notifications.reader.scan()
        return Rig(viewModel: viewModel, mac: mac)
    }

    private func closable(
        title: String = "Maya", body: String = "Lunch?", persistent: Bool = false
    ) -> FixtureNode {
        .banner(title: title, body: body, persistent: persistent, actions: [NotificationRoles.press, Self.closeAction])
    }

    @Test func inTheIslandShowsABannerWithOpenAndDismiss() async throws {
        let rig = await rig()
        let system = closable()
        rig.mac.show(system)
        await rig.mirror.reader.scan()

        let banner = try #require(rig.viewModel.banner)
        #expect(banner.title == "Messages: Maya" && banner.detail == "Lunch?")
        #expect(banner.systemImage == "bell.fill" && banner.tint == Theme.Tint.neutral)
        #expect(banner.actions.map(\.title) == ["Open", "Dismiss"])
        #expect(system.performed == [Self.closeAction], "the system\u{2019}s banner was closed, and not pressed")
        #expect(rig.mirror.inbox.items.count == 1)

        rig.viewModel.performBannerAction(at: 1)
        #expect(rig.viewModel.banner == nil && rig.mirror.inbox.items.isEmpty, "Dismiss is done with it")

        rig.mac.show(closable(title: "Sam"))
        await rig.mirror.reader.scan()
        #expect(rig.viewModel.banner?.title == "Messages: Sam")
        rig.viewModel.performBannerAction(at: 0)
        #expect(rig.viewModel.banner == nil && rig.mirror.inbox.items.isEmpty, "Open takes it off the inbox too")
    }

    @Test func inTheCornerShowsNothingInTheIsland() async {
        let rig = await rig(placement: .corner)
        let system = closable()
        rig.mac.show(system)
        await rig.mirror.reader.scan()
        #expect(rig.viewModel.banner == nil && rig.viewModel.alert == nil)
        #expect(system.performed.isEmpty, "macOS\u{2019}s banner is left alone")
        #expect(rig.mirror.inbox.items.map(\.title) == ["Maya"], "and the inbox keeps it")
    }

    @Test func aPersistentAlertIsNeverClosed() async {
        let rig = await rig()
        let alert = closable(title: "Meeting", persistent: true)
        rig.mac.show(alert)
        await rig.mirror.reader.scan()
        #expect(alert.performed.isEmpty)
        #expect((rig.mac.window).moves.isEmpty, "and its window isn\u{2019}t moved either")
        #expect(rig.viewModel.banner?.title == "Messages: Meeting", "the island shows it as well")
        #expect(rig.mirror.inbox.items.first?.isPersistent == true)
    }

    @Test func aBannerThatCantBeClosedStaysInTheCornerAndIsSaidOnce() async {
        let rig = await rig()
        // No close action and no window to move: the banner is the whole tree.
        rig.mac.root = .banner(title: "One", actions: [NotificationRoles.press])
        await rig.mirror.reader.scan()
        #expect(rig.mirror.couldntCloseBanner)
        #expect(rig.viewModel.banner?.title == "Notifications Stay in the Corner")
        #expect(rig.mirror.inbox.items.map(\.title) == ["One"], "it is kept")

        rig.viewModel.dismissBanner()
        rig.mac.root = .banner(title: "Two", actions: [NotificationRoles.press])
        await rig.mirror.reader.scan()
        #expect(rig.viewModel.banner == nil, "said once")
        #expect(rig.mirror.inbox.items.map(\.title) == ["Two", "One"])
    }

    @Test func quietInFocusHoldsMirroredBanners() async {
        let rig = await rig()
        rig.viewModel.settings.quietDuringFocus = true
        rig.viewModel.features.focus.update(true)
        let held = closable(title: "Held")
        rig.mac.show(held)
        await rig.mirror.reader.scan()
        #expect(rig.viewModel.banner == nil)
        #expect(held.performed.isEmpty, "macOS\u{2019}s banner is not closed for a banner that won\u{2019}t show")
        #expect(rig.mirror.inbox.items.map(\.title) == ["Held"])

        rig.viewModel.features.focus.update(false)
        rig.mac.show(closable(title: "After"))
        await rig.mirror.reader.scan()
        #expect(rig.viewModel.banner?.title == "Messages: After")
    }

    @Test func aMutedEventKeepsMacOSsBanner() async {
        let rig = await rig()
        rig.viewModel.settings.setMuted(.notification, true)
        let system = closable()
        rig.mac.show(system)
        await rig.mirror.reader.scan()
        #expect(rig.viewModel.banner == nil && system.performed.isEmpty)
        #expect(rig.mirror.inbox.items.count == 1)
    }

    @Test func theWidgetShowsTheNewest() {
        let mirror = NotificationMirror(reader: NotificationReader(environment: .inert))
        for index in 0..<6 {
            mirror.inbox.add(
                MirroredNotification(
                    id: "n\(index)", app: "Mail", title: "T\(index)", subtitle: "", body: "", isPersistent: false,
                    date: Date()))
        }
        #expect([GridSize(3, 1), GridSize(3, 2), GridSize(6, 2)].map(NotificationsWidget.rowCount(for:)) == [2, 4, 4])
        #expect(mirror.inbox.latest(NotificationsWidget.rowCount(for: GridSize(3, 1))).map(\.id) == ["n5", "n4"])
        #expect(mirror.inbox.latest(NotificationsWidget.rowCount(for: GridSize(3, 2))).map(\.id) == ["n5", "n4", "n3", "n2"])
        mirror.inbox.clear()
        #expect(mirror.inbox.latest(2).isEmpty, "Clear empties it")

        let descriptor = WidgetCatalog.descriptor(builtIn: .notifications)
        #expect(descriptor.sizes == [GridSize(3, 1), GridSize(3, 2), GridSize(6, 2)])
        #expect(descriptor.defaultSize == GridSize(3, 1))
    }

    @Test func theWidgetIsOfferedOnlyWhileItsFeatureIsOn() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "MacIslandNotifications.\(UUID().uuidString)")!)
        let widget = WidgetID.builtIn(.notifications)
        #expect(WidgetCatalog.feature(of: widget) == .notifications)
        #expect(!settings.isWidgetAllowed(widget))
        settings.setOn(.notifications, true)
        #expect(settings.isWidgetAllowed(widget))
        if let added = settings.homeLayout.adding(widget, size: GridSize(3, 1)) { settings.setHomeLayout(added) }
        #expect(settings.homeLayout.isPlaced(widget))
        settings.setOn(.notifications, false)
        #expect(!settings.homeLayout.isPlaced(widget) && settings.homeHiddenByFeature.contains(widget))
    }

    @Test func turningOffEmptiesEverything() async {
        let rig = await rig()
        rig.mirror.stop()  // the rig starts it; begin from the feature switch instead
        let viewModel = rig.viewModel
        let runner = FeatureRunner(features: viewModel.features, viewModel: viewModel, music: { _ in }, screenshots: { _ in })
        viewModel.settings.onFeatureChange = { runner.apply($0) }
        runner.startAtLaunch()
        #expect(rig.mac.observed == 1, "off, nothing more was started at launch")

        viewModel.settings.setOn(.notifications, true)
        #expect(rig.mirror.reader.status == .running && rig.mac.observed == 2)
        await rig.mirror.reader.scan()
        rig.mac.show(closable())
        await rig.mirror.reader.scan()
        #expect(rig.mirror.inbox.items.count == 1)

        viewModel.settings.setOn(.notifications, false)
        #expect(rig.mirror.inbox.items.isEmpty && rig.mirror.reader.status == .off)
        #expect(rig.mac.stopped == 2)
        #expect(FeatureNotice.whatStops(.notifications, features: viewModel.features) == nil, "nothing left to clear")
    }

    @Test func thePlacementIsKeptAndArchived() throws {
        let defaults = UserDefaults(suiteName: "MacIslandPlacement.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.notificationPlacement == .corner, "nothing new on the island until it is chosen")
        settings.notificationPlacement = .island
        #expect(AppSettings(defaults: defaults).notificationPlacement == .island)
        #expect(SettingsArchive.make(from: settings).notificationPlacement == "In the Island")
        #expect(InstallEvidence.keys.contains("notifications.placement"))
    }

    @Test func theMirroredEventsAreListedOnlyWhileTheFeatureIsOn() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "MacIslandMirrored.\(UUID().uuidString)")!)
        #expect(AmbientEvent.notification.group == .mirrored)
        #expect(
            NotificationsPane.requirement(for: .notification, settings: settings) == "Turn on Notifications in Features.")
        settings.setOn(.notifications, true)
        #expect(NotificationsPane.requirement(for: .notification, settings: settings) == nil)
        #expect(NotificationsPane.mirroredFooter(couldntClose: false).contains("never closed"))
        #expect(NotificationsPane.mirroredFooter(couldntClose: true).contains("stayed in the corner"))
    }
}
