import Foundation
import Observation

/// Where a notification shows (Notifications → Mirrored). Two places at once would double every interruption, so there is no both.
enum NotificationPlacement: String, CaseIterable, Identifiable {
    /// macOS shows its banner where it always does; MacIsland only keeps the inbox.
    case corner = "In the Corner, with an Inbox"
    /// The island shows each one, and the system's banner is closed.
    case island = "In the Island"

    var id: Self { self }
}

/// The Notifications feature: the reader that notices a notification, the inbox that keeps the recent ones, and, when the person chose
/// the island, the banner that takes the system's place. Off, nothing is listening and nothing is kept.
@MainActor
@Observable
final class NotificationMirror {
    let reader: NotificationReader
    let inbox: NotificationInbox

    /// Closing the system's banner failed once; the notification stayed in the corner. Shown in Notifications, and said once on the island.
    private(set) var couldntCloseBanner = false

    @ObservationIgnored private let placement: () -> NotificationPlacement
    @ObservationIgnored private var lockToken: NSObjectProtocol?
    @ObservationIgnored private var saidSo = false

    /// Whether the island would show a banner now: it isn't muted, no full-screen app has the display, and no Focus is holding banners.
    @ObservationIgnored var canShow: () -> Bool = { false }
    /// Puts a banner on the island.
    @ObservationIgnored var show: (IslandBanner) -> Void = { _ in }

    init(
        reader: NotificationReader, inbox: NotificationInbox? = nil,
        placement: @escaping () -> NotificationPlacement = { .corner }
    ) {
        self.reader = reader
        self.inbox = inbox ?? NotificationInbox()
        self.placement = placement
        reader.onArrival = { [weak self] in self?.arrived($0) }
    }

    /// Lets the island show what is read.
    func connect(to viewModel: IslandViewModel) {
        canShow = { [weak viewModel] in viewModel?.canShowBanner(for: .notification) ?? false }
        show = { [weak viewModel] in viewModel?.showBanner($0, for: .seconds(6), event: .notification) }
    }

    /// Why it isn't working, for the feature's row; nil while it works or is off.
    var problem: String? { reader.status.problem }

    /// Starts reading, if Accessibility allows it. Never asks.
    func start() {
        reader.start()
        watchLock()
    }

    /// Stops reading and forgets everything read.
    func stop() {
        reader.stop()
        inbox.clear()
        couldntCloseBanner = false
        saidSo = false
        if let lockToken { DistributedNotificationCenter.default().removeObserver(lockToken) }
        lockToken = nil
    }

    // MARK: Arrivals

    /// Keeps the notification, then, if the island is where they show and it can show this one, closes the system's banner and shows
    /// it there. The banner is closed first: if it can't be, the notification stays where macOS put it and is not shown twice. A
    /// persistent alert is never closed (it waits for an answer the island can't give), so it shows in both.
    func arrived(_ arrival: NotificationReader.Arrival) {
        let notification = arrival.notification
        inbox.add(notification)
        guard placement() == .island, canShow() else { return }
        if !notification.isPersistent, !reader.close(arrival.banner) {
            noteCouldntClose()
            return
        }
        show(banner(for: notification))
    }

    func banner(for notification: MirroredNotification) -> IslandBanner {
        Announcements.mirrored(
            notification, open: { [weak self] in self?.open(notification) },
            dismiss: { [weak self] in self?.inbox.remove(notification.id) })
    }

    /// Opens a notification and takes it off the inbox: its banner is pressed if it is still there, else its app opens.
    func open(_ notification: MirroredNotification) {
        inbox.remove(notification.id)
        let reader = reader
        Task { await reader.open(notification) }
    }

    private func noteCouldntClose() {
        couldntCloseBanner = true
        guard !saidSo else { return }
        saidSo = true
        show(Announcements.couldntCloseNotification)
    }

    /// What was read is not kept past the screen locking.
    private func watchLock() {
        guard lockToken == nil else { return }
        lockToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inbox.screenLocked() }
        }
    }
}

extension NotificationReader.Environment {
    /// An environment that reaches nothing and has no access, for the Settings preview and for tests that don't read notifications.
    static var inert: Self {
        Self(
            hasAccess: { false }, root: { nil }, observe: { _ in false }, stopObserving: {}, isCenterOpen: { false },
            openApp: { _ in false }, closeNames: ["Close"])
    }
}
