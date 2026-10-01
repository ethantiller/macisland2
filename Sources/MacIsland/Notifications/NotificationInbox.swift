import Foundation
import Observation

/// A notification Notification Center showed, as read from its banner. Memory only: it is never written to disk or sent anywhere.
struct MirroredNotification: Identifiable, Equatable {
    /// The banner's own identifier, which holds a UUID; two readings of the same banner have the same id.
    let id: String
    var app: String
    var title: String
    var subtitle: String
    var body: String
    /// An alert, which stays until the person answers it, rather than a banner that goes by itself.
    var isPersistent: Bool
    var date: Date

    /// "Messages: Maya", or just the app when the banner has no title.
    var headline: String {
        let name = app.isEmpty ? "Notification" : app
        return title.isEmpty ? name : "\(name): \(title)"
    }

    /// The first line of what it says: the body, or the subtitle when there is no body.
    var detail: String? {
        for text in [body, subtitle] {
            if let line = text.split(whereSeparator: \.isNewline).first.map(String.init), !line.isEmpty { return line }
        }
        return nil
    }
}

/// The recent notifications, newest first. At most fifty, kept only in memory, and emptied when the screen locks and when the feature
/// turns off.
@MainActor
@Observable
final class NotificationInbox {
    static let capacity = 50

    private(set) var items: [MirroredNotification] = []

    /// Adds a notification at the front. One already here (the same banner read again) is left where it is.
    func add(_ notification: MirroredNotification) {
        guard !items.contains(where: { $0.id == notification.id }) else { return }
        items.insert(notification, at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        if !items.isEmpty { items = [] }
    }

    /// The newest `count`, for the Home widget.
    func latest(_ count: Int) -> [MirroredNotification] {
        Array(items.prefix(count))
    }

    /// The screen locked: what was read is not kept past it.
    func screenLocked() {
        clear()
    }
}
