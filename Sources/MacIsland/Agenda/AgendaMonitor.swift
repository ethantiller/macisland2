import AppKit
import EventKit
import Observation
import SwiftUI

/// One upcoming event or due reminder.
struct AgendaItem: Equatable, Identifiable {
    enum Kind { case event, reminder }

    /// Unique per occurrence, so a repeating event announces each time.
    let id: String
    let kind: Kind
    let title: String
    let date: Date
    /// The reminder's identifier in the store, to mark it done.
    var reminderID: String?
    /// A Zoom, Meet, Teams, or Webex link found in the event.
    var joinURL: URL?
}

/// One open reminder in the Reminders tab.
struct ReminderRow: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    /// Whether the due date names a time, or only a day.
    let hasTime: Bool

    /// Dated reminders first, soonest (or most overdue) at the top; undated ones after, in the order given.
    static func sorted(_ rows: [ReminderRow]) -> [ReminderRow] {
        let dated = rows.filter { $0.due != nil }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        return dated + rows.filter { $0.due == nil }
    }

    /// "Overdue", the time if it's today, the weekday within a week, otherwise the date. Empty without a due date.
    func dueText(now: Date, calendar: Calendar = .current) -> String {
        guard let due else { return "" }
        if hasTime, due < now { return "Overdue" }
        if !hasTime, calendar.startOfDay(for: due) < calendar.startOfDay(for: now) { return "Overdue" }
        if calendar.isDate(due, inSameDayAs: now) {
            return hasTime ? due.formatted(date: .omitted, time: .shortened) : "Today"
        }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day
            ?? 0
        if days == 1 { return "Tomorrow" }
        return days < 7
            ? due.formatted(.dateTime.weekday(.abbreviated)) : due.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Finds the video-call link in an event's location, notes, or URL.
enum MeetingLink {
    private static let pattern = try! NSRegularExpression(
        pattern:
            #"https?://[^\s<>"']*(?:zoom\.us|zoom\.com|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com)[^\s<>"']*"#,
        options: [.caseInsensitive]
    )

    static func find(in texts: [String?]) -> URL? {
        for case let text? in texts {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = pattern.firstMatch(in: text, range: range),
                let matched = Range(match.range, in: text)
            else { continue }
            let link = String(text[matched]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)>]"))
            if let url = URL(string: link) { return unwrap(url) }
        }
        return nil
    }

    /// The real address behind a security rewrite: Outlook's SafeLinks (`url=`) and Google's redirect (`q=`).
    /// Anything else, including a link whose inner address is not http(s), is returned as it is.
    nonisolated static func unwrap(_ url: URL) -> URL {
        var current = url
        for _ in 0..<3 {  // a rewritten link can itself be rewritten
            guard let host = current.host?.lowercased(),
                let components = URLComponents(url: current, resolvingAgainstBaseURL: false)
            else { break }
            let parameter: String?
            if host.hasSuffix(".safelinks.protection.outlook.com") || host == "safelinks.protection.outlook.com" {
                parameter = "url"
            } else if (host == "google.com" || host.hasSuffix(".google.com")) && current.path == "/url" {
                parameter = "q"
            } else {
                parameter = nil
            }
            guard let parameter,
                let value = components.queryItems?.first(where: { $0.name == parameter })?.value,
                let inner = URL(string: value), ["http", "https"].contains(inner.scheme?.lowercased())
            else { break }
            current = inner
        }
        return current
    }

    /// The meeting app's own address for a link: Teams `msteams:/l/...` and Zoom `zoommtg://zoom.us/join?...`.
    /// `nil` for anything else. Whether the app is installed is `joinURL`'s question.
    nonisolated static func appURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        if host == "teams.microsoft.com", url.path.hasPrefix("/l/") {
            return URL(
                string: "msteams:" + components.percentEncodedPath
                    + (components.percentEncodedQuery.map { "?" + $0 } ?? ""))
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us"), url.path.hasPrefix("/j/") {
            let id = url.path.dropFirst(3).split(separator: "/").first.map(String.init) ?? ""
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
            var link = URLComponents()
            link.scheme = "zoommtg"
            link.host = "zoom.us"
            link.path = "/join"
            link.queryItems = [URLQueryItem(name: "confno", value: id)]
            if let password = components.queryItems?.first(where: { $0.name == "pwd" })?.value {
                link.queryItems?.append(URLQueryItem(name: "pwd", value: password))
            }
            return link.url
        }
        return nil
    }

    /// What Join opens: the meeting app when the link has one and this Mac has it, otherwise the link itself.
    @MainActor
    static func joinURL(
        for url: URL, hasHandler: (URL) -> Bool = { NSWorkspace.shared.urlForApplication(toOpen: $0) != nil }
    ) -> URL {
        if let app = appURL(for: url), hasHandler(app) { return app }
        return url
    }

    @MainActor
    static func join(_ url: URL) {
        NSWorkspace.shared.open(joinURL(for: url))
    }
}

/// The timing rules, separate from EventKit so they can be tested.
enum AgendaRules {
    /// A banner this long before an event starts.
    static let eventLead: TimeInterval = 5 * 60
    /// Reminders that came due while the island was off aren't announced later than this.
    static let reminderGrace: TimeInterval = 10 * 60

    /// Whichever comes first.
    static func next(in items: [AgendaItem]) -> AgendaItem? {
        items.min { $0.date < $1.date }
    }

    /// The soonest few, in order.
    static func upcoming(in items: [AgendaItem], limit: Int = 4) -> [AgendaItem] {
        Array(items.sorted { $0.date < $1.date }.prefix(limit))
    }

    static func shouldAnnounce(_ item: AgendaItem, now: Date) -> Bool {
        switch item.kind {
        case .event: item.date > now - 60 && item.date <= now + eventLead
        case .reminder: item.date <= now + 60 && item.date > now - reminderGrace
        }
    }

    static func timeText(for item: AgendaItem, now: Date) -> String {
        let interval = item.date.timeIntervalSince(now)
        if interval < -60 { return item.kind == .reminder ? "Overdue" : "Started" }
        if interval < 60 { return "Now" }
        if interval < 3600 { return "in \(Int((interval / 60).rounded(.up))) min" }
        return item.date.formatted(date: .omitted, time: .shortened)
    }
}

/// Watches the calendar and Reminders for the next thing, and announces it when it's close.
/// Each source is asked for access only once it's turned on in Settings.
@MainActor
@Observable
final class AgendaMonitor {
    private(set) var next: AgendaItem?
    /// The next few things, soonest first (up to 4), for the taller Today widgets.
    private(set) var upcoming: [AgendaItem] = []
    /// Open reminders for the Reminders tab. Loaded while that tab is open.
    private(set) var reminderRows: [ReminderRow] = []
    /// Reminders access was refused, so the tab offers "Allow Access".
    private(set) var remindersDenied = false

    /// A source is on but macOS access was refused; the empty state offers "Allow Access".
    private(set) var isDenied = false

    /// Called once per item when it's about to start or has just come due.
    @ObservationIgnored var onAnnounce: ((AgendaItem) -> Void)?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var wantsCalendar = false
    @ObservationIgnored private var wantsReminders = false
    /// Whether loading in the background may show the system prompt. False at launch: a permission macOS hasn't decided is only
    /// read, never asked for, until the person turns a setting on or opens the Reminders tab.
    @ObservationIgnored private var mayAsk = false
    @ObservationIgnored private var listIsShown = false
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var timer: Timer?

    /// Puts an item in Up Next without asking the calendar: for the Settings preview, which is sample data.
    func showSample(_ item: AgendaItem?, upcoming: [AgendaItem] = [], reminders: [ReminderRow] = []) {
        next = item
        self.upcoming = upcoming
        reminderRows = reminders
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Lets macOS fire it with other wakeups instead of on its own.
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// `mayAsk` is false for the launch, so a permission that was reset (every rebuild resets them) isn't asked for until the person
    /// chooses; true when a setting is changed, which is the choice.
    func configure(calendar: Bool, reminders: Bool, mayAsk: Bool = true) {
        wantsCalendar = calendar
        wantsReminders = reminders
        self.mayAsk = mayAsk
        refresh()
    }

    func refresh() {
        Task {
            await reload()
            if listIsShown { await loadReminderRows() }
        }
    }

    /// Loads the Reminders tab's list, asking for access the first time. Call when the tab appears.
    func showReminderList() async {
        listIsShown = true
        await loadReminderRows()
    }

    func hideReminderList() {
        listIsShown = false
    }

    private func loadReminderRows() async {
        guard await hasAccess(.reminder, asking: true) else {
            remindersDenied = true
            reminderRows = []
            return
        }
        remindersDenied = false
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let rows: [ReminderRow] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(
                    returning: (reminders ?? []).map { reminder in
                        let components = reminder.dueDateComponents
                        return ReminderRow(
                            id: reminder.calendarItemIdentifier,
                            title: reminder.title ?? "Reminder",
                            due: components?.date,
                            hasTime: components?.hour != nil
                        )
                    })
            }
        }
        withAnimation(Theme.Motion.resize) { reminderRows = ReminderRow.sorted(rows) }
    }

    /// Marks a reminder done from the list.
    func complete(reminderID id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        withAnimation(Theme.Motion.resize) { reminderRows.removeAll { $0.id == id } }
        refresh()
    }

    func complete(_ item: AgendaItem) {
        guard let id = item.reminderID, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            return
        }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        refresh()
    }

    /// Adds a reminder to the default list. Asks for access the first time.
    func addReminder(title: String) async -> Bool {
        guard await hasAccess(.reminder, asking: true) else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        do {
            try store.save(reminder, commit: true)
        } catch {
            return false
        }
        refresh()
        return true
    }

    static func openRemindersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Loading

    private func reload() async {
        var items: [AgendaItem] = []
        var denied = false
        if wantsCalendar {
            if await hasAccess(.event, asking: mayAsk) { items += events() } else { denied = true }
        }
        if wantsReminders {
            if await hasAccess(.reminder, asking: mayAsk) { items += await reminders() } else { denied = true }
        }
        isDenied = denied

        let now = Date()
        next = AgendaRules.next(in: items)
        upcoming = AgendaRules.upcoming(in: items)

        let due = items.filter { AgendaRules.shouldAnnounce($0, now: now) && !announced.contains($0.id) }
        announced.formUnion(due.map(\.id))
        if let first = AgendaRules.next(in: due) { onAnnounce?(first) }
    }

    /// Asks for access to `type` if it was never asked, and says whether it is allowed. The same request the Calendar and
    /// Reminders switches and the Reminders tab make; the first-run guide calls it so a person is asked in one place.
    func requestAccess(to type: EKEntityType) async -> Bool { await hasAccess(type, asking: true) }

    /// Whether `type` is allowed. Shows the system prompt only when `asking` and it was never asked.
    private func hasAccess(_ type: EKEntityType, asking: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess:
            return true
        case .notDetermined:
            guard asking else { return false }
            let granted =
                type == .event
                ? try? await store.requestFullAccessToEvents()
                : try? await store.requestFullAccessToReminders()
            return granted ?? false
        default:
            return false
        }
    }

    private func events() -> [AgendaItem] {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-600), end: now.addingTimeInterval(86_400), calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.startDate >= now.addingTimeInterval(-600) }
            .map { event in
                AgendaItem(
                    id: "\(event.eventIdentifier ?? event.title ?? "event")@\(event.startDate.timeIntervalSince1970)",
                    kind: .event,
                    title: event.title ?? "Event",
                    date: event.startDate,
                    joinURL: MeetingLink.find(in: [event.location, event.notes, event.url?.absoluteString])
                )
            }
    }

    private func reminders() async -> [AgendaItem] {
        let now = Date()
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: now.addingTimeInterval(-86_400), ending: now.addingTimeInterval(86_400), calendars: nil
        )
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items: [AgendaItem] = (reminders ?? []).compactMap { reminder in
                    guard let due = reminder.dueDateComponents?.date else { return nil }
                    // A date-only reminder is due at the start of the day; count it from 9:00.
                    let date =
                        reminder.dueDateComponents?.hour == nil
                        ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
                        : due
                    return AgendaItem(
                        id: "\(reminder.calendarItemIdentifier)@\(date.timeIntervalSince1970)",
                        kind: .reminder,
                        title: reminder.title ?? "Reminder",
                        date: date,
                        reminderID: reminder.calendarItemIdentifier
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }
}
