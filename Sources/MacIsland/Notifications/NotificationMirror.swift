import Foundation
import Observation

/// The Notifications feature: the reader that notices a notification, and the inbox that keeps the recent ones. Off, nothing is
/// listening and nothing is kept.
@MainActor
@Observable
final class NotificationMirror {
    let reader: NotificationReader
    let inbox: NotificationInbox

    @ObservationIgnored private var lockToken: NSObjectProtocol?

    init(reader: NotificationReader, inbox: NotificationInbox = NotificationInbox()) {
        self.reader = reader
        self.inbox = inbox
        reader.onArrival = { [weak self] in self?.arrived($0) }
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
        if let lockToken { DistributedNotificationCenter.default().removeObserver(lockToken) }
        lockToken = nil
    }

    func arrived(_ arrival: NotificationReader.Arrival) {
        inbox.add(arrival.notification)
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
