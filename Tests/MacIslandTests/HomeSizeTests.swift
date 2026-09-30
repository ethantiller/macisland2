import Foundation
import Testing

@testable import MacIsland

/// What each size of a Home widget shows: the timers' segments, the tools, the forecast, what is next.
struct HomeSizeTests {
    @Test func everySizeOfEveryWidgetFitsTheGridAlone() {
        for widget in BuiltInWidget.allCases {
            for size in WidgetCatalog.descriptor(builtIn: widget).sizes {
                #expect(HomeGridSpec.pack([size]).first != nil, "\(widget) \(size)")
            }
        }
    }

    @Test func sizesReadAsColumnsByRows() {
        #expect(GridSize(3, 1).displayName == "3 \u{00D7} 1")
    }

    // MARK: Timers & Shelf

    @Test func theTimersPillShowsMoreSegmentsAsItGrows() {
        #expect([2, 3, 4, 5, 6].map(HomeAction.segments(forColumns:)) == [2, 3, 4, 4, 4])
        func ids(_ segments: Int, pomodoro: Bool = false) -> [String] {
            HomeAction.list(
                timerActive: false, pomodoroActive: pomodoro, stopwatchActive: false, shelfCount: 0, segments: segments
            ).map(\.id)
        }
        #expect(ids(2) == ["timer5", "timer25"])
        #expect(ids(3) == ["timer5", "timer25", "pomodoro"])
        #expect(ids(4) == ["timer5", "timer25", "pomodoro", "shelf"])
        #expect(ids(2, pomodoro: true) == ["timer5", "timer25", "runningPomodoro"], "a running clock is always shown")
    }

    @Test func theOptionsStillApplyAtEverySize() {
        let actions = HomeAction.list(
            timerActive: true, pomodoroActive: false, stopwatchActive: false, shelfCount: 2, timerMinutes: [10, 45],
            showsPomodoro: false, showsShelf: true, segments: 4)
        #expect(actions.map(\.id) == ["runningTimer", "shelf"])
    }

    // MARK: Quick Tools

    @Test func quickToolsShowsAnumberOfToolsByItsSize() {
        let counts = [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1), GridSize(6, 1), GridSize(6, 2)]
            .map(QuickActionsGrid.toolCount(for:))
        #expect(counts == [4, 4, 6, 8, ToolID.allCases.count])
    }

    @Test func theChosenToolsComeFirstAndOthersFillTheRest() {
        let pinned: [ToolID] = [.keepAwake, .ringLight, .muteMic, .screenshot]
        let followed = QuickActionsGrid.tools(for: GridSize(3, 1), chosen: nil, pinned: pinned)
        #expect(followed.count == 6 && Array(followed.prefix(4)) == pinned)
        let chosen = QuickActionsGrid.tools(for: GridSize(1, 1), chosen: [.focus, .mirror], pinned: pinned)
        #expect(chosen.count == 4 && Array(chosen.prefix(2)) == [.focus, .mirror])
        #expect(Set(chosen).count == chosen.count, "no tool twice")
        #expect(QuickActionsGrid.tools(for: GridSize(6, 2), chosen: [.focus], pinned: pinned) == ToolID.allCases)
    }

    @Test func theInspectorPadsChosenToolsToTheSlotsOfASize() {
        let filled = WidgetInspector.filled([.focus], to: 8)
        #expect(filled.count == 8 && filled.first == .focus && Set(filled).count == 8)
        #expect(WidgetInspector.filled([.focus, .mirror, .cleanKeyboard], to: 2) == [.focus, .mirror])
    }

    // MARK: Forecast

    private func place() -> WeatherModel.Place { .init(name: "Paris", latitude: 48.85, longitude: 2.35) }

    private let forecast = #"""
        {"utc_offset_seconds":7200,
         "current":{"temperature_2m":18.4,"weather_code":2,"is_day":1},
         "hourly":{"time":["2026-09-30T14:00","2026-09-30T15:00","2026-09-30T16:00","2026-09-30T17:00","2026-09-30T18:00","2026-09-30T19:00"],
                   "temperature_2m":[18.4,19.0,19.2,18.1,17.0,15.3],"weather_code":[2,2,1,0,0,1],"is_day":[1,1,1,1,1,0]},
         "daily":{"time":["2026-09-30","2026-10-01","2026-10-02","2026-10-03","2026-10-04"],
                  "weather_code":[2,3,61,1,0],"temperature_2m_max":[24.4,26.0,19.0,22.0,25.0],
                  "temperature_2m_min":[12.0,13.0,11.0,10.0,12.4]}}
        """#

    @Test func theForecastGivesTheNextFiveHoursAndFiveDays() throws {
        let conditions = try #require(WeatherModel.parseConditions(Data(forecast.utf8), place: place()))
        #expect(conditions.temperature == 18)
        #expect(conditions.hours.map(\.hour) == [15, 16, 17, 18, 19], "the hours after this one, in the place's time")
        #expect(conditions.hours.map(\.temperature) == [19, 19, 18, 17, 15])
        #expect(conditions.hours.last?.symbol == "moon.stars.fill", "7 PM is night in this forecast")
        #expect(conditions.days.map(\.label) == ["Today", "Thu", "Fri", "Sat", "Sun"])
        #expect(conditions.days.map(\.high) == [24, 26, 19, 22, 25])
        #expect(conditions.days.map(\.low) == [12, 13, 11, 10, 12])
    }

    @Test func aForecastWithoutHoursOrDaysStillGivesTheConditions() throws {
        let json = #"{"current":{"temperature_2m":18.4,"weather_code":2,"is_day":1}}"#
        let conditions = try #require(WeatherModel.parseConditions(Data(json.utf8), place: place()))
        #expect(conditions.hours.isEmpty && conditions.days.isEmpty && conditions.place == "Paris")
    }

    @Test func theRequestAsksForTheHoursAndDaysInTheSameCall() throws {
        let url = try #require(WeatherModel.forecastURL(place: place(), fahrenheit: false))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("hourly") == "temperature_2m,weather_code,is_day" && value("forecast_hours") == "6")
        #expect(value("daily") == "weather_code,temperature_2m_max,temperature_2m_min" && value("forecast_days") == "5")
        #expect(url.host == "api.open-meteo.com", "no new host")
    }

    @Test func theSampleForecastIsWhatThePreviewShows() throws {
        let conditions = try #require(
            WeatherModel.parseConditions(PreviewSamples.forecast(), place: place()))
        #expect(conditions.hours.count == 5 && conditions.days.count == 5 && conditions.days.first?.label == "Today")
    }

    // MARK: What is next

    @Test func upcomingIsTheSoonestFewInOrder() {
        let now = Date()
        func item(_ id: String, _ minutes: Double) -> AgendaItem {
            AgendaItem(id: id, kind: .event, title: id, date: now.addingTimeInterval(minutes * 60))
        }
        let items = [item("d", 50), item("a", 5), item("e", 90), item("c", 30), item("b", 10)]
        #expect(AgendaRules.upcoming(in: items).map(\.id) == ["a", "b", "c", "d"])
        #expect(AgendaRules.upcoming(in: items, limit: 2).map(\.id) == ["a", "b"])
        #expect(AgendaRules.upcoming(in: []).isEmpty)
    }

    @MainActor
    @Test func theSampleAgendaShowsUpcomingAndReminders() {
        let agenda = AgendaMonitor()
        agenda.showSample(
            PreviewSamples.nextEvent(), upcoming: PreviewSamples.upcoming(), reminders: PreviewSamples.reminders())
        #expect(agenda.upcoming.first?.id == agenda.next?.id)
        #expect(agenda.upcoming.map(\.date) == agenda.upcoming.map(\.date).sorted())
        #expect(agenda.reminderRows.count == 4)
    }

    // MARK: Words and lines

    @Test func remindersAndNotesShowMoreAtTheTallerSizes() {
        #expect(
            [GridSize(2, 1), GridSize(3, 1), GridSize(3, 2), GridSize(6, 2)].map(RemindersWidget.rowCount(for:)) == [
                2, 2, 4, 4,
            ])
        #expect(
            [GridSize(2, 1), GridSize(3, 1), GridSize(3, 2), GridSize(6, 2)].map(NoteWidget.lineCount(for:)) == [
                1, 2, 6, 6,
            ])
    }

    // MARK: Presets and the editor

    @Test func listeningAndDashboardAreThreeRowsThatFit() {
        for name in ["Listening", "Dashboard"] {
            let layout = HomeLayout.presets.first { $0.name == name }?.layout
            #expect(layout?.rowsUsed() == 3, "\(name)")
            #expect(layout.map { HomeLayout.normalized($0) == $0 } == true, "\(name)")
        }
        let listening = HomeLayout.presets.first { $0.name == "Listening" }?.layout
        #expect(listening?.widgets.first?.size == GridSize(6, 2))
    }

    @MainActor
    @Test func theInspectorsSizeRowChangesTheSizeAndUndoPutsItBack() {
        let name = "MacIslandSize.\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: name)!)
        let editor = HomeEditor(settings: settings)
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        let original = settings.homeLayout
        let music = original.widgets[1]

        undo.beginUndoGrouping()
        editor.setSize(GridSize(3, 2), for: music.id)
        undo.endUndoGrouping()
        #expect(settings.homeLayout.widgets[1].size == GridSize(3, 2))
        undo.undo()
        #expect(settings.homeLayout == original)

        // A size that would leave something off Home is refused, and says so.
        editor.setSize(GridSize(6, 2), for: original.widgets[2].id)
        #expect(settings.homeLayout == original)
        #expect(editor.refusal?.contains("fit") == true)
    }
}
