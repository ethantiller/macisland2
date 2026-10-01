import CoreGraphics
import Foundation
import Testing

@testable import MacIsland

// MARK: Doubles

/// A node of a made-up accessibility tree.
final class FixtureNode: AXNodeReading, @unchecked Sendable {
    var role: String?
    var subrole: String?
    var identifier: String?
    var value: String?
    var children: [any AXNodeReading]
    var actions: [String]
    var position: CGPoint?
    private(set) var performed: [String] = []
    private(set) var moves: [CGPoint] = []

    init(
        role: String? = nil, subrole: String? = nil, identifier: String? = nil, value: String? = nil,
        actions: [String] = [], position: CGPoint? = nil, children: [any AXNodeReading] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.value = value
        self.actions = actions
        self.position = position
        self.children = children
    }

    func perform(_ action: String) -> Bool {
        performed.append(action)
        return actions.contains(action)
    }

    func setPosition(_ point: CGPoint) -> Bool {
        moves.append(point)
        position = point
        return true
    }

    // MARK: Building a tree

    static func text(_ identifier: String, _ value: String) -> FixtureNode {
        FixtureNode(role: NotificationRoles.text, identifier: identifier, value: value)
    }

    /// A banner as Notification Center draws it: a group with a UUID in its identifier, and a text for each field.
    static func banner(
        app: String = "Messages", title: String = "Maya", subtitle: String = "", body: String = "Lunch?",
        uuid: String = UUID().uuidString, persistent: Bool = false, actions: [String] = [NotificationRoles.press]
    ) -> FixtureNode {
        var texts = [text("header", app), text("title", title)]
        if !subtitle.isEmpty { texts.append(text("subtitle", subtitle)) }
        if !body.isEmpty { texts.append(text("body", body)) }
        return FixtureNode(
            role: "AXGroup", subrole: persistent ? NotificationRoles.alert : NotificationRoles.banner,
            identifier: "notification-\(uuid)", actions: actions, children: [FixtureNode(role: "AXGroup", children: texts)])
    }

    /// The application, with one window holding a stack of the banners.
    static func center(_ banners: [FixtureNode] = []) -> FixtureNode {
        FixtureNode(
            role: "AXApplication",
            children: [
                FixtureNode(
                    role: NotificationRoles.window, position: CGPoint(x: 900, y: 40),
                    children: [FixtureNode(role: "AXGroup", subrole: "AXNotificationCenterBannerStack", children: banners)])
            ])
    }
}

/// Counts steps instead of reading the time, so a cap on seconds is tested without waiting.
final class StepClock: @unchecked Sendable {
    private var time = 0.0
    let step: Double

    init(step: Double) { self.step = step }

    func now() -> TimeInterval {
        time += step
        return time
    }
}

/// A Mac with a Notification Center to read, and a record of what the reader did to it.
@MainActor
final class FixtureMac {
    var root: FixtureNode
    var hasAccess = true
    var isCenterOpen = false
    var canObserve = true
    var apps: Set<String> = []
    private(set) var observed = 0
    private(set) var stopped = 0
    private(set) var opened: [String] = []
    private var change: (@MainActor () -> Void)?

    init(banners: [FixtureNode] = []) { root = .center(banners) }

    /// The stack the banners sit in.
    var stack: FixtureNode {
        // application > window > stack
        let window = root.children[0] as! FixtureNode
        return window.children[0] as! FixtureNode
    }

    var window: FixtureNode { root.children[0] as! FixtureNode }

    func show(_ banner: FixtureNode) { stack.children.append(banner) }

    func remove(_ banner: FixtureNode) { stack.children.removeAll { ($0 as? FixtureNode) === banner } }

    /// The tree changed, as the observer would say.
    func notifyChange() { change?() }

    /// The pause is long, so a scan runs only when a test asks for it.
    var environment: NotificationReader.Environment {
        NotificationReader.Environment(
            hasAccess: { self.hasAccess },
            root: { self.root },
            observe: { change in
                self.observed += 1
                self.change = change
                return self.canObserve
            },
            stopObserving: { self.stopped += 1 },
            isCenterOpen: { self.isCenterOpen },
            openApp: { name in
                self.opened.append(name)
                return self.apps.contains(name)
            },
            closeNames: ["Close", "Fermer"],
            debounce: .seconds(3600))
    }

    func reader() -> NotificationReader { NotificationReader(environment: environment) }
}

@MainActor
final class Arrivals {
    private(set) var all: [NotificationReader.Arrival] = []

    init(_ reader: NotificationReader) {
        reader.onArrival = { [self] in all.append($0) }
    }

    var titles: [String] { all.map(\.notification.title) }
}

// MARK: Tests

@MainActor
struct NotificationReaderTests {
    @Test func aBannerIsReadWithItsAppTitleAndBody() throws {
        let uuid = "0F3B2A10-6C1D-4E7A-9B54-2D8E1C7A9F30"
        let banner = FixtureNode.banner(
            app: "Mail", title: "Receipt from Orchard", subtitle: "Your order", body: "Thanks for shopping.\nSee you.",
            uuid: uuid)
        let result = BannerScanner.scan(FixtureNode.center([banner]))
        let read = try #require(result.banners.first)
        #expect(result.banners.count == 1)
        #expect(read.app == "Mail" && read.title == "Receipt from Orchard")
        #expect(read.subtitle == "Your order" && read.body == "Thanks for shopping.\nSee you.")
        #expect(read.identifier == uuid, "its identity is the UUID in its identifier")
        let notification = read.notification()
        #expect(notification.headline == "Mail: Receipt from Orchard")
        #expect(notification.detail == "Thanks for shopping.", "the first line of the body")
        #expect(
            MirroredNotification(
                id: "1", app: "Calendar", title: "Design Review", subtitle: "In 10 minutes", body: "", isPersistent: false,
                date: Date()
            ).detail == "In 10 minutes", "the subtitle stands in for a missing body")
    }

    @Test func aBannerWithoutAUUIDIsToldApartByWhatItSays() throws {
        let one = FixtureNode.banner(title: "One")
        let two = FixtureNode.banner(title: "Two")
        one.identifier = "banner"
        two.identifier = "banner"
        let result = BannerScanner.scan(FixtureNode.center([one, two]))
        #expect(result.banners.count == 2)
        #expect(Set(result.banners.map(\.identifier)).count == 2)
    }

    @Test func anAlertStaysAndABannerGoes() async {
        let mac = FixtureMac()
        let reader = mac.reader()
        let arrivals = Arrivals(reader)
        reader.start()
        await reader.scan()  // the first scan records what is showing

        let banner = FixtureNode.banner(title: "Banner")
        let alert = FixtureNode.banner(title: "Alert", persistent: true, actions: [NotificationRoles.press, "Name:Close"])
        mac.show(banner)
        mac.show(alert)
        await reader.scan()
        #expect(arrivals.titles == ["Banner", "Alert"])
        #expect(arrivals.all.map(\.notification.isPersistent) == [false, true])

        mac.remove(banner)
        await reader.scan()
        #expect(arrivals.all.count == 2, "a banner going away is not an arrival")
        mac.show(FixtureNode.banner(title: "Next"))
        await reader.scan()
        #expect(arrivals.titles == ["Banner", "Alert", "Next"], "the alert still showing is not announced again")
    }

    @Test func theFirstScanRecordsWithoutAnnouncing() async {
        let mac = FixtureMac(banners: [FixtureNode.banner(title: "Already here")])
        let reader = mac.reader()
        let arrivals = Arrivals(reader)
        reader.start()
        #expect(reader.status == .running)
        await reader.scan()
        #expect(arrivals.all.isEmpty)
        await reader.scan()
        #expect(arrivals.all.isEmpty, "and not on the next scan either")
        mac.show(FixtureNode.banner(title: "New"))
        await reader.scan()
        #expect(arrivals.titles == ["New"])
    }

    @Test func nothingIsReadWhileNotificationCenterItselfIsOpen() async {
        let mac = FixtureMac()
        let reader = mac.reader()
        let arrivals = Arrivals(reader)
        reader.start()
        await reader.scan()
        mac.isCenterOpen = true
        mac.show(FixtureNode.banner(title: "Inside the panel"))
        await reader.scan()
        #expect(arrivals.all.isEmpty)
        mac.isCenterOpen = false
        await reader.scan()
        #expect(arrivals.titles == ["Inside the panel"], "it is read once the panel is closed")
    }

    @Test func theScanStopsAtItsCaps() {
        // Nodes: a thousand banners-to-be are cut at 384.
        let wide = FixtureNode(
            role: "AXApplication", children: (0..<1000).map { _ in FixtureNode(role: "AXGroup") })
        let widest = BannerScanner.scan(wide)
        #expect(widest.visited == ScanLimits().nodes && widest.wasCut)

        // Depth: a banner at the ninth level is read, and one at the twentieth is not.
        func chain(_ levels: Int, ending leaf: FixtureNode) -> FixtureNode {
            var node = leaf
            for _ in 0..<levels { node = FixtureNode(role: "AXGroup", children: [node]) }
            return node
        }
        let near = BannerScanner.scan(chain(8, ending: .banner(title: "Near")))
        #expect(near.banners.map(\.title) == ["Near"])
        let far = BannerScanner.scan(chain(20, ending: .banner(title: "Far")))
        #expect(far.banners.isEmpty && far.wasCut)

        // Time: a clock that moves a tenth of a second per read gives up after about seven.
        let clock = StepClock(step: 0.1)
        let slow = BannerScanner.scan(wide, now: { clock.now() })
        #expect(slow.visited < 10 && slow.wasCut)
    }

    @Test func theInboxKeepsFiftyNewestFirst() {
        let inbox = NotificationInbox()
        for index in 0..<60 {
            inbox.add(
                MirroredNotification(
                    id: "n\(index)", app: "Messages", title: "T\(index)", subtitle: "", body: "", isPersistent: false,
                    date: Date()))
        }
        #expect(inbox.items.count == 50 && NotificationInbox.capacity == 50)
        #expect(inbox.items.first?.id == "n59" && inbox.items.last?.id == "n10")
        inbox.add(inbox.items[5])
        #expect(inbox.items.count == 50 && inbox.items[5].id == "n54", "the same banner twice is kept once, where it was")
        #expect(inbox.latest(2).map(\.id) == ["n59", "n58"])
    }

    @Test func lockEmptiesTheInbox() {
        let mirror = NotificationMirror(reader: NotificationReader(environment: .inert))
        mirror.inbox.add(
            MirroredNotification(
                id: "1", app: "Mail", title: "Hello", subtitle: "", body: "", isPersistent: false, date: Date()))
        #expect(mirror.inbox.items.count == 1)
        mirror.inbox.screenLocked()
        #expect(mirror.inbox.items.isEmpty)
    }

    @Test func turningTheFeatureOffEmptiesTheInboxAndStopsListening() async {
        let mac = FixtureMac()
        let mirror = NotificationMirror(reader: mac.reader())
        mirror.start()
        await mirror.reader.scan()
        mac.show(FixtureNode.banner(title: "Kept"))
        await mirror.reader.scan()
        #expect(mirror.inbox.items.map(\.title) == ["Kept"])
        mirror.stop()
        #expect(mirror.inbox.items.isEmpty && mirror.reader.status == .off)
        #expect(mac.stopped == 1)
    }

    @Test func openPressesTheSameBannerOrOpensTheApp() async {
        let mac = FixtureMac()
        mac.apps = ["Messages"]
        let reader = mac.reader()
        reader.start()
        await reader.scan()
        let banner = FixtureNode.banner(app: "Messages", title: "Maya")
        mac.show(banner)
        let notification = banner.notification()

        #expect(await reader.open(notification), "the banner is still there")
        #expect(banner.performed == [NotificationRoles.press])
        #expect(mac.opened.isEmpty)

        mac.remove(banner)
        #expect(await reader.open(notification), "the banner has gone, so its app opens")
        #expect(mac.opened == ["Messages"])
        #expect(banner.performed == [NotificationRoles.press], "a banner that is gone is not pressed")

        mac.apps = []
        #expect(await reader.open(notification) == false, "and nothing opens for an app that isn't there")
    }

    @Test func withoutAccessibilityNothingStarts() async {
        let mac = FixtureMac()
        mac.hasAccess = false
        let reader = mac.reader()
        let arrivals = Arrivals(reader)
        reader.start()
        #expect(reader.status == .needsAccess)
        #expect(reader.status.problem?.contains("Accessibility") == true)
        #expect(mac.observed == 0, "no listener was made")
        mac.show(FixtureNode.banner())
        await reader.scan()
        #expect(arrivals.all.isEmpty)

        mac.hasAccess = true
        reader.start()
        #expect(reader.status == .running && mac.observed == 1, "it starts once Accessibility is on")
    }

    @Test func accessTakenAwayStopsTheListener() async {
        let mac = FixtureMac()
        let reader = mac.reader()
        reader.start()
        mac.hasAccess = false
        await reader.scan()
        #expect(reader.status == .needsAccess && mac.stopped == 1)
    }

    @Test func aTreeThatCantBeListenedToIsSaidToBeUnreadable() {
        let mac = FixtureMac()
        mac.canObserve = false
        let reader = mac.reader()
        reader.start()
        #expect(reader.status == .unreadable)
        #expect(reader.status.problem == "Notifications couldn\u{2019}t be read on this version of macOS.")
    }

    @Test func closeUsesTheCloseActionOrMovesTheWindowAway() throws {
        let names: Set<String> = ["Close", "Fermer"]
        #expect(
            BannerCloser.closeAction(in: ["AXPress", "Name:Fermer\nTarget:0x0\nSelector:(null)"], named: names)
                == "Name:Fermer\nTarget:0x0\nSelector:(null)")
        #expect(BannerCloser.closeAction(in: ["AXPress", "Name:Reply\nTarget:0x0"], named: names) == nil)

        let closable = FixtureNode.banner(actions: [NotificationRoles.press, "Name:Close\nTarget:0x0\nSelector:(null)"])
        let found = try #require(BannerScanner.scan(FixtureNode.center([closable])).banners.first)
        #expect(BannerCloser.close(found, named: names))
        #expect(closable.performed == ["Name:Close\nTarget:0x0\nSelector:(null)"])

        let stubborn = FixtureNode.banner(actions: [NotificationRoles.press])
        let tree = FixtureNode.center([stubborn])
        let stuck = try #require(BannerScanner.scan(tree).banners.first)
        let window = try #require(tree.children.first as? FixtureNode)
        #expect(BannerCloser.close(stuck, named: names), "with no close action, its window is moved away")
        #expect(window.moves == [BannerCloser.farAway])

        let nowhere = FixtureNode.banner(actions: [])
        let lone = try #require(BannerScanner.scan(nowhere).banners.first)
        #expect(BannerCloser.close(lone, named: names) == false, "and with no window either, it can't be closed")
    }
}
