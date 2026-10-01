import CoreGraphics
import Foundation
import Observation

/// One node of an accessibility tree, as far as the reader needs it. The live tree is Notification Center's (`AXElementNode`); tests walk
/// a fixture, so the reader is checked without a Mac that shows a banner.
protocol AXNodeReading: Sendable {
    var role: String? { get }
    var subrole: String? { get }
    var identifier: String? { get }
    var value: String? { get }
    var children: [any AXNodeReading] { get }
    var actions: [String] { get }
    var position: CGPoint? { get }
    @discardableResult func perform(_ action: String) -> Bool
    @discardableResult func setPosition(_ point: CGPoint) -> Bool
}

/// The names this reads Notification Center's tree by. None of them is documented: Notification Center is a system process, and a macOS
/// update can rename any of them, after which the reader finds nothing (`NotificationReader.Status.unreadable` says so).
enum NotificationRoles {
    /// A banner that goes by itself, and an alert that stays until it is answered.
    static let banner = "AXNotificationCenterBanner"
    static let alert = "AXNotificationCenterAlert"
    static let window = "AXWindow"
    static let text = "AXStaticText"
    static let press = "AXPress"
    /// The text fields of a banner, by the identifier of their `AXStaticText`.
    static let header = "header", title = "title", subtitle = "subtitle", body = "body"
    static let fields: Set<String> = [header, title, subtitle, body]

    /// Whether the subrole is a notification, and whether it stays.
    static func isPersistent(subrole: String) -> Bool? {
        switch subrole {
        case banner: false
        case alert: true
        default: nil
        }
    }

    /// The first UUID in `text`, upper case. A banner's identifier holds one, and it is what tells one banner from the next.
    static func uuid(in text: String?) -> String? {
        guard let text,
            let range = text.range(
                of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                options: .regularExpression)
        else { return nil }
        return String(text[range]).uppercased()
    }
}

/// How much of the tree one scan may read. Notification Center answers slowly when it is busy, and a scan must never be the reason the
/// Mac feels slow.
struct ScanLimits: Sendable, Equatable {
    var seconds: TimeInterval = 0.8
    var nodes = 384
    var depth = 10
}

/// A banner found in the tree: what it says, and the nodes that can act on it.
struct ScannedBanner {
    let identifier: String
    let app: String
    let title: String
    let subtitle: String
    let body: String
    let isPersistent: Bool
    let node: any AXNodeReading
    /// The window it sits in, which is what moves off screen when the banner has no close action.
    let window: (any AXNodeReading)?

    func notification(at date: Date = Date()) -> MirroredNotification {
        MirroredNotification(
            id: identifier, app: app, title: title, subtitle: subtitle, body: body, isPersistent: isPersistent,
            date: date)
    }
}

struct ScanResult {
    var banners: [ScannedBanner] = []
    var visited = 0
    /// A cap cut the scan short: what was found is all there is to know, but there may have been more.
    var wasCut = false
}

/// Reads the banners out of a tree. Pure: it touches the nodes it is given and nothing else.
enum BannerScanner {
    static func scan(
        _ root: any AXNodeReading, limits: ScanLimits = ScanLimits(),
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> ScanResult {
        let walker = Walker(limits: limits, now: now)
        walker.walk(root, depth: 0, window: nil)
        return ScanResult(banners: walker.banners, visited: walker.visited, wasCut: walker.wasCut)
    }

    /// How deep below a banner its text may sit.
    private static let textDepth = 6

    private final class Walker {
        let limits: ScanLimits
        let now: @Sendable () -> TimeInterval
        let deadline: TimeInterval
        var visited = 0
        var wasCut = false
        var isExhausted = false
        var banners: [ScannedBanner] = []

        init(limits: ScanLimits, now: @escaping @Sendable () -> TimeInterval) {
            self.limits = limits
            self.now = now
            deadline = now() + limits.seconds
        }

        /// Counts one node against the caps; false once a cap is reached.
        func spend() -> Bool {
            if isExhausted { return false }
            if visited >= limits.nodes || now() >= deadline {
                isExhausted = true
                wasCut = true
                return false
            }
            visited += 1
            return true
        }

        func walk(_ node: any AXNodeReading, depth: Int, window: (any AXNodeReading)?) {
            guard depth <= limits.depth else {
                wasCut = true
                return
            }
            guard spend() else { return }
            let window = node.role == NotificationRoles.window ? node : window
            if let subrole = node.subrole, let persistent = NotificationRoles.isPersistent(subrole: subrole) {
                if let banner = read(node, persistent: persistent, window: window) { banners.append(banner) }
                return
            }
            for child in node.children {
                if isExhausted { return }
                walk(child, depth: depth + 1, window: window)
            }
        }

        private func read(_ node: any AXNodeReading, persistent: Bool, window: (any AXNodeReading)?) -> ScannedBanner? {
            var fields: [String: String] = [:]
            var uuid = NotificationRoles.uuid(in: node.identifier)
            collect(node, depth: 0, into: &fields, uuid: &uuid)
            guard fields.values.contains(where: { !$0.isEmpty }) else { return nil }
            let app = fields[NotificationRoles.header] ?? ""
            let title = fields[NotificationRoles.title] ?? ""
            let subtitle = fields[NotificationRoles.subtitle] ?? ""
            let body = fields[NotificationRoles.body] ?? ""
            // A banner whose identifier carries no UUID is told apart by what it says.
            let identifier = uuid ?? "text-\([app, title, subtitle, body].joined(separator: "\u{1F}").hashValue)"
            return ScannedBanner(
                identifier: identifier, app: app, title: title, subtitle: subtitle, body: body, isPersistent: persistent,
                node: node, window: window)
        }

        private func collect(
            _ node: any AXNodeReading, depth: Int, into fields: inout [String: String], uuid: inout String?
        ) {
            guard depth < BannerScanner.textDepth else {
                wasCut = true
                return
            }
            for child in node.children {
                guard spend() else { return }
                let identifier = child.identifier
                if uuid == nil { uuid = NotificationRoles.uuid(in: identifier) }
                if child.role == NotificationRoles.text, let key = identifier?.lowercased(),
                    NotificationRoles.fields.contains(key), fields[key] == nil, let text = child.value
                {
                    fields[key] = text
                } else {
                    collect(child, depth: depth + 1, into: &fields, uuid: &uuid)
                }
            }
        }
    }
}

/// Describes a tree in lines, for the spike on a new macOS: the roles, subroles, identifiers, action names, and how long each text is.
/// Never the words themselves, so a log of it holds nothing anyone wrote.
enum AXTreeDump {
    static func lines(_ root: any AXNodeReading, limits: ScanLimits = ScanLimits()) -> [String] {
        var lines: [String] = []
        var visited = 0
        func walk(_ node: any AXNodeReading, depth: Int) {
            guard depth <= limits.depth, visited < limits.nodes else { return }
            visited += 1
            var parts = [node.role ?? "-"]
            if let subrole = node.subrole { parts.append("subrole=\(subrole)") }
            if let identifier = node.identifier { parts.append("id=\(identifier)") }
            if let value = node.value { parts.append("text=\(value.count) chars") }
            let actions = node.actions
            if !actions.isEmpty { parts.append("actions=" + actions.map { $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ")) }
            lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
            for child in node.children { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return lines
    }
}

/// Takes a banner away from the screen, so the island can show it instead.
enum BannerCloser {
    /// Where a window with no close action is sent, far from any display.
    static let farAway = CGPoint(x: -20_000, y: -20_000)

    /// The action that closes: custom actions are named "Name:Close\nTarget:0x0\nSelector:(null)", so the name is what follows "Name:".
    static func closeAction(in actions: [String], named names: Set<String>) -> String? {
        actions.first { action in
            let name = action.hasPrefix("Name:") ? String(action.dropFirst(5).prefix { !$0.isNewline }) : action
            return names.contains(name)
        }
    }

    /// Whether the banner is gone from the screen: closed by its own action, or else its window moved away (and put back a moment
    /// later, because Notification Center reuses the window for the next banner).
    static func close(_ banner: ScannedBanner, named names: Set<String>) -> Bool {
        if let action = closeAction(in: banner.node.actions, named: names), banner.node.perform(action) { return true }
        guard let window = banner.window, let origin = window.position, window.setPosition(farAway) else { return false }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            window.setPosition(origin)
        }
        return true
    }
}

/// Knows when Notification Center shows a notification. It listens to the accessibility tree of `com.apple.notificationcenterui`
/// (needs Accessibility, no private API), and scans it a moment after it changes: event-driven, no timer. The first scan only records
/// what is already showing. Nothing is read while Notification Center itself is open.
@MainActor
@Observable
final class NotificationReader {
    enum Status: Equatable {
        case off
        /// Accessibility isn't allowed, so nothing started.
        case needsAccess
        case running
        /// Notification Center couldn't be listened to: the tree or its roles aren't what this build knows.
        case unreadable

        /// Why it isn't working, for the feature's row. Nil while it works or is off.
        var problem: String? {
            switch self {
            case .off, .running: nil
            case .needsAccess: "Needs Accessibility. Turn it on in System Settings."
            case .unreadable: "Notifications couldn\u{2019}t be read on this version of macOS."
            }
        }
    }

    struct Arrival {
        let notification: MirroredNotification
        let banner: ScannedBanner
    }

    /// What the reader reaches the Mac through, so a test can stand in for all of it.
    struct Environment {
        var hasAccess: () -> Bool
        /// The root of Notification Center's tree, or nil when it can't be reached.
        var root: () -> (any AXNodeReading)?
        /// Starts listening; `onChange` is called on the main actor whenever the tree changes. False when it can't.
        var observe: (@escaping @MainActor () -> Void) -> Bool
        var stopObserving: () -> Void
        /// Notification Center's own panel is showing.
        var isCenterOpen: () -> Bool
        /// Opens the app named in a banner's header. False when there is none by that name.
        var openApp: (String) -> Bool
        /// The names of the close action ("Close", and its translation).
        var closeNames: Set<String>
        var debounce: Duration = .milliseconds(120)
        /// Write what each scan saw to the log (`MACISLAND_NOTIFICATION_DEBUG=1`), without any words, to check the roles on a new macOS.
        var dumpsTree = false
        var log: (String) -> Void = { NSLog("%@", $0) }
    }

    private(set) var status: Status = .off
    /// Called for each banner that wasn't there at the last scan.
    @ObservationIgnored var onArrival: ((Arrival) -> Void)?

    @ObservationIgnored private let environment: Environment
    @ObservationIgnored private let limits: ScanLimits
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var seenOrder: [String] = []
    @ObservationIgnored private var hasScanned = false
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var rescanQueued = false
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// How many banner identifiers are remembered, so the same one read again isn't announced twice.
    private static let seenLimit = 200

    init(environment: Environment, limits: ScanLimits = ScanLimits()) {
        self.environment = environment
        self.limits = limits
    }

    /// Starts listening, if Accessibility allows it. Never asks.
    func start() {
        guard status != .running else { return }
        guard environment.hasAccess() else {
            status = .needsAccess
            return
        }
        resetMemory()
        guard environment.observe({ [weak self] in self?.schedule() }) else {
            status = .unreadable
            return
        }
        status = .running
        schedule()  // the first scan records what is already showing
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if status == .running { environment.stopObserving() }
        status = .off
        resetMemory()
    }

    private func resetMemory() {
        seen = []
        seenOrder = []
        hasScanned = false
        rescanQueued = false
    }

    /// Reads the tree a moment after the last change, so a banner that is still building is read once.
    func schedule() {
        guard status == .running else { return }
        debounceTask?.cancel()
        let pause = environment.debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            await self?.scan()
        }
    }

    /// Reads the tree once and announces each banner not seen before. The tree is read off the main thread: it can be slow.
    func scan() async {
        guard status == .running else { return }
        guard environment.hasAccess() else {
            environment.stopObserving()
            status = .needsAccess
            return
        }
        guard !environment.isCenterOpen() else { return }
        guard !isScanning else {
            rescanQueued = true
            return
        }
        guard let root = environment.root() else { return }
        isScanning = true
        let limits = limits
        let dumps = environment.dumpsTree
        let (result, dump) = await Task.detached(priority: .utility) {
            (BannerScanner.scan(root, limits: limits), dumps ? AXTreeDump.lines(root, limits: limits) : [])
        }.value
        isScanning = false
        guard status == .running else { return }
        if dumps {
            environment.log(
                "Notification Center tree (\(result.banners.count) banners read, \(result.visited) nodes):\n"
                    + dump.joined(separator: "\n"))
        }
        announce(result)
        if rescanQueued {
            rescanQueued = false
            schedule()
        }
    }

    private func announce(_ result: ScanResult) {
        let isFirst = !hasScanned
        hasScanned = true
        for banner in result.banners where !seen.contains(banner.identifier) {
            remember(banner.identifier)
            guard !isFirst else { continue }
            onArrival?(Arrival(notification: banner.notification(), banner: banner))
        }
    }

    private func remember(_ identifier: String) {
        seen.insert(identifier)
        seenOrder.append(identifier)
        if seenOrder.count > Self.seenLimit {
            seen.remove(seenOrder.removeFirst())
        }
    }

    /// Opens a notification: presses its banner if the same banner is still showing, and otherwise opens its app.
    @discardableResult
    func open(_ notification: MirroredNotification) async -> Bool {
        if let banner = await find(notification.id), banner.node.perform(NotificationRoles.press) { return true }
        return environment.openApp(notification.app)
    }

    private func find(_ id: String) async -> ScannedBanner? {
        guard status == .running, !environment.isCenterOpen(), let root = environment.root() else { return nil }
        let limits = limits
        let result = await Task.detached(priority: .utility) { BannerScanner.scan(root, limits: limits) }.value
        return result.banners.first { $0.identifier == id }
    }

    /// Takes the banner off the screen. False when it couldn't be, and the system's banner is still there.
    func close(_ banner: ScannedBanner) -> Bool {
        BannerCloser.close(banner, named: environment.closeNames)
    }
}
