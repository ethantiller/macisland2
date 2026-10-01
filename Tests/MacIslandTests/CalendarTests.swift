import Foundation
import Testing

@testable import MacIsland

@MainActor
struct CalendarTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(
        _ id: String, start: Date, minutes: Int = 60, allDay: Bool = false
    ) -> AgendaItem {
        AgendaItem(
            id: id, kind: .event, title: id, date: start, end: start.addingTimeInterval(Double(minutes) * 60),
            calendarID: "cal", isAllDay: allDay)
    }

    // MARK: Time left

    @Test func anEventInProgressStaysUntilItEndsWithTimeLeftOn() {
        let start = date(1, 10)
        let end = start.addingTimeInterval(3600)
        let during = start.addingTimeInterval(30 * 60)
        #expect(AgendaRules.keepsEvent(start: start, end: end, now: during, showsTimeLeft: true))
        #expect(!AgendaRules.keepsEvent(start: start, end: end, now: end.addingTimeInterval(1), showsTimeLeft: true))
        #expect(AgendaRules.keepsEvent(start: start, end: end, now: start.addingTimeInterval(-3600), showsTimeLeft: true))
    }

    @Test func withTimeLeftOffAnEventLeavesTenMinutesInAsToday() {
        let start = date(1, 10)
        let end = start.addingTimeInterval(3600)
        #expect(AgendaRules.keepsEvent(start: start, end: end, now: start.addingTimeInterval(9 * 60), showsTimeLeft: false))
        #expect(!AgendaRules.keepsEvent(start: start, end: end, now: start.addingTimeInterval(11 * 60), showsTimeLeft: false))
        // And its words are unchanged: "Started" once it has begun.
        let item = event("a", start: start)
        let text = AgendaRules.timeText(for: item, now: start.addingTimeInterval(5 * 60))
        #expect(text == "Started")
    }

    @Test func timeLeftWords() {
        let start = date(1, 10)
        let item = event("a", start: start, minutes: 90)
        func words(after minutes: Double) -> String {
            AgendaRules.timeText(for: item, now: start.addingTimeInterval(minutes * 60), showsTimeLeft: true)
        }
        #expect(words(after: 65) == "Ends in 25 min")
        #expect(words(after: 89.5) == "Ends in 1 min", "never zero minutes")
        #expect(words(after: 5).hasPrefix("Ends "), "over an hour left is a time")
        #expect(!words(after: 5).contains("in "))
        // Not in progress: the usual words.
        #expect(AgendaRules.timeText(for: item, now: start.addingTimeInterval(-600), showsTimeLeft: true) == "in 10 min")
        // A reminder has no end.
        let reminder = AgendaItem(id: "r", kind: .reminder, title: "r", date: start)
        #expect(AgendaRules.timeText(for: reminder, now: start.addingTimeInterval(300), showsTimeLeft: true) == "Overdue")
    }

    @Test func theEventOnNowComesBeforeALaterOneWhileTimeLeftIsOn() {
        let now = date(1, 10, 30)
        let current = event("current", start: date(1, 10), minutes: 90)
        let later = event("later", start: date(1, 11))
        let earlierEnded = event("ended", start: date(1, 9), minutes: 30)
        #expect(AgendaRules.next(in: [later, current], now: now, prefersInProgress: true)?.id == "current")
        #expect(AgendaRules.next(in: [later, earlierEnded, current], now: now)?.id == "ended", "as today")
        #expect(AgendaRules.next(in: [later], now: now, prefersInProgress: true)?.id == "later")
        #expect(AgendaRules.isInProgress(current, now: now) && !AgendaRules.isInProgress(later, now: now))
    }

    // MARK: Which calendars

    @Test func aHiddenCalendarIsLeftOutAndANewOneShowsByDefault() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.hiddenCalendars.isEmpty && !settings.isCalendarHidden("work"))
        var calls = 0
        settings.onAgendaChange = { calls += 1 }
        settings.setCalendarHidden("work", true)
        settings.setCalendarHidden("work", true)
        #expect(settings.isCalendarHidden("work") && calls == 1, "does nothing unless it changes")
        #expect(!settings.isCalendarHidden("added-later"), "a calendar nobody left out counts")
        settings.setCalendarHidden("work", false)
        #expect(!settings.isCalendarHidden("work") && calls == 2)
    }

    @Test func hiddenCalendarsAndTimeLeftAreStoredButOnlyTimeLeftTravels() throws {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.showsTimeLeft = true
        settings.setCalendarHidden("local-id", true)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.showsTimeLeft && reloaded.isCalendarHidden("local-id"))

        // Calendar identifiers belong to this Mac, so the settings file carries the switch and not the list.
        let data = try SettingsArchive.make(from: settings).data()
        #expect(!String(decoding: data, as: UTF8.self).contains("local-id"))
        let target = AppSettings(defaults: freshDefaults())
        target.restore(try SettingsArchive.read(data))
        #expect(target.showsTimeLeft && target.hiddenCalendars.isEmpty)
    }

    @Test func calendarsAreGroupedByAccountAndSorted() {
        let groups = CalendarGroup.groups(from: [
            (source: "s2", sourceTitle: "iCloud", id: "c3", title: "Work"),
            (source: "s1", sourceTitle: "Google", id: "c1", title: "Sam"),
            (source: "s2", sourceTitle: "iCloud", id: "c2", title: "Home"),
            (source: "s3", sourceTitle: "iCloud", id: "c4", title: "Other"),
        ])
        #expect(groups.map(\.title) == ["Google", "iCloud", "iCloud"], "sorted by name")
        #expect(groups.map(\.id) == ["s1", "s2", "s3"], "two accounts called iCloud stay two groups")
        #expect(groups[1].calendars.map(\.title) == ["Home", "Work"])
    }

    // MARK: The month

    @Test func eventDaysMarkTheRightCells() {
        let items = [
            event("a", start: date(14, 10)),
            event("b", start: date(14, 15)),
            event("c", start: date(20, 9), minutes: 24 * 60 * 2),  // 20th 9:00 to 22nd 9:00: three days
            event("d", start: date(5, 0), minutes: 24 * 60, allDay: true),  // all day on the 5th only
            event("outside", start: calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!),
        ]
        let days = AgendaRules.eventDays(items, inMonthOf: date(15, 12), calendar: calendar)
        #expect(Set(days.keys) == [5, 14, 20, 21, 22], "the two-day event is on each day it touches")
        #expect(days[14]?.map(\.id) == ["a", "b"], "soonest first")
        #expect(days[20]?.map(\.id) == ["c"] && days[21]?.map(\.id) == ["c"] && days[22]?.map(\.id) == ["c"])
        #expect(days[5]?.map(\.id) == ["d"])

        // The cells that get a dot are the grid's days.
        let weeks = MonthGrid.weeks(containing: date(15, 12), calendar: calendar)
        let shown = Set(weeks.flatMap { $0 }.compactMap { $0 })
        #expect(Set(days.keys).isSubset(of: shown))
    }

    @Test func aChosenDayNamesItsFirstEventAndHowManyMore() {
        let items = [event("Design review", start: date(14, 10)), event("Lunch", start: date(14, 12))]
        let line = AgendaRules.dayLine(for: date(14, 0), items: items, calendar: calendar)
        #expect(line.contains("Design review") && line.contains("1 more") && line.contains("14"))
        let alone = AgendaRules.dayLine(for: date(14, 0), items: [items[0]], calendar: calendar)
        #expect(!alone.contains("more"))
        let allDay = AgendaRules.dayLine(
            for: date(5, 0), items: [event("Holiday", start: date(5, 0), minutes: 1440, allDay: true)], calendar: calendar)
        #expect(allDay.contains("all day"))
    }

    @Test func theDayChoiceClearsWithEscAndWhenTheCalendarCloses() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.calendarSelectedDay = 14
        #expect(viewModel.stepBack() && viewModel.calendarSelectedDay == nil)
        viewModel.calendarSelectedDay = 3
        viewModel.setCalendarExpanded(false)
        #expect(viewModel.calendarSelectedDay == nil)
    }

    @Test func theRunnerPassesTimeLeftAndTheHiddenCalendarsToTheAgenda() {
        // The agenda is configured with the choices (it only reads them; no calendar is touched without access).
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.showsTimeLeft = true
        viewModel.settings.setCalendarHidden("x", true)
        FeatureRunner.configureAgenda(viewModel.features, mayAsk: false)
        viewModel.agenda.stop()
        #expect(viewModel.settings.showsTimeLeft && viewModel.settings.isCalendarHidden("x"))
    }

    // MARK: Countdowns (K2)

    @Test func aCountdownShowsOnlyInTheHourBefore() {
        let now = date(1, 10)
        let soon = event("soon", start: now.addingTimeInterval(50 * 60))
        let far = event("far", start: now.addingTimeInterval(2 * 3600))
        let started = event("started", start: now.addingTimeInterval(-60))
        let allDay = event("allday", start: now.addingTimeInterval(600), allDay: true)
        let everything = [far, soon, started, allDay]
        #expect(AgendaRules.countdown(in: everything, now: now, all: true, chosen: [])?.id == "soon")
        #expect(AgendaRules.countdown(in: [far], now: now, all: true, chosen: []) == nil, "more than an hour away")
        #expect(AgendaRules.countdown(in: [started], now: now, all: true, chosen: []) == nil, "it ends when the event starts")
        #expect(AgendaRules.countdown(in: [allDay], now: now, all: true, chosen: []) == nil, "an all-day event has no start time")
        // Chosen, and not all: only the chosen one.
        #expect(AgendaRules.countdown(in: [soon], now: now, all: false, chosen: []) == nil)
        #expect(AgendaRules.countdown(in: [soon], now: now, all: false, chosen: ["soon"])?.id == "soon")
        let reminder = AgendaItem(id: "r", kind: .reminder, title: "r", date: now.addingTimeInterval(300))
        #expect(AgendaRules.countdown(in: [reminder], now: now, all: true, chosen: []) == nil)
    }

    @Test func theMenuOffersCountdownOnlyForTimedEventsNotStarted() {
        let now = date(1, 10)
        #expect(AgendaRules.canCountDown(event("a", start: now.addingTimeInterval(600)), now: now))
        #expect(!AgendaRules.canCountDown(event("a", start: now.addingTimeInterval(-600)), now: now))
        #expect(!AgendaRules.canCountDown(event("a", start: now.addingTimeInterval(600), allDay: true), now: now))
        let reminder = AgendaItem(id: "r", kind: .reminder, title: "r", date: now.addingTimeInterval(60))
        #expect(!AgendaRules.canCountDown(reminder, now: now))
    }

    @Test func aChosenCountdownSurvivesARelaunchAndIsPrunedAfter() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        let now = Date()
        let soon = AgendaItem(
            id: "e1@1", kind: .event, title: "Soon", date: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400))
        let past = AgendaItem(
            id: "e2@2", kind: .event, title: "Past", date: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        settings.setCountdown(for: soon, true)
        settings.setCountdown(for: past, true)
        settings.setCountdown(for: soon, true)
        #expect(settings.hasCountdown(soon.id) && settings.hasCountdown(past.id))

        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.hasCountdown(soon.id), "it survives")
        relaunched.pruneCountdowns(now: now)
        #expect(relaunched.hasCountdown(soon.id) && !relaunched.hasCountdown(past.id), "a finished event's is forgotten")
        #expect(!AppSettings(defaults: defaults).hasCountdown(past.id), "and stays forgotten")
        relaunched.setCountdown(for: soon, false)
        #expect(!relaunched.hasCountdown(soon.id))
    }

    private func standup() -> AgendaItem {
        let now = Date()
        return AgendaItem(
            id: "e@1", kind: .event, title: "Standup", date: now.addingTimeInterval(20 * 60),
            end: now.addingTimeInterval(50 * 60))
    }

    @Test func everyEventCountsDownWhenOnAndTheSwitchTravels() throws {
        let viewModel = TestSupport.makeViewModel()
        let settings = viewModel.settings
        settings.setOn(.calendar, true)
        let event = standup()
        viewModel.agenda.showSample(event, upcoming: [event])
        #expect(viewModel.activeCountdown == nil, "off: nothing is counted down")
        settings.countsDownToEveryEvent = true
        #expect(viewModel.activeCountdown?.id == event.id)
        #expect(viewModel.compactActivities == [.countdown(event)])

        let target = AppSettings(defaults: freshDefaults())
        target.restore(try SettingsArchive.read(SettingsArchive.make(from: settings).data()))
        #expect(target.countsDownToEveryEvent)
        settings.setOn(.calendar, false)
        #expect(viewModel.activeCountdown == nil, "Calendar off: no countdown")
    }

    @Test func aChosenCountdownCountsDownWithoutTheEverySwitch() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.calendar, true)
        let event = standup()
        viewModel.agenda.showSample(event, upcoming: [event])
        #expect(viewModel.activeCountdown == nil)
        viewModel.settings.setCountdown(for: event, true)
        #expect(viewModel.activeCountdown?.id == event.id)
    }

    @Test func aCountdownRanksAfterTheStopwatch() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.calendar, true)
        viewModel.settings.countsDownToEveryEvent = true
        let event = standup()
        viewModel.agenda.showSample(event, upcoming: [event])
        viewModel.timer.start(minutes: 5)
        viewModel.stopwatch.toggle()
        defer {
            viewModel.timer.reset()
            viewModel.stopwatch.reset()
        }
        #expect(viewModel.compactActivities == [.timer, .stopwatch, .countdown(event)])
        #expect(viewModel.compactPair?.leading == .timer && viewModel.compactPair?.trailing == .stopwatch)
        viewModel.timer.reset()
        viewModel.stopwatch.reset()
        #expect(viewModel.compactActivity == .countdown(event))
        var song = NowPlayingState()
        song.title = "Song"
        song.isPlaying = true
        song.playbackRate = 1
        song.duration = 200
        song.timestamp = Date()
        viewModel.nowPlaying.apply(song)
        #expect(viewModel.compactActivities == [.countdown(event), .media], "it pairs with music")
    }

    private func freshDefaults() -> UserDefaults {
        let name = "MacIslandCalendar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
