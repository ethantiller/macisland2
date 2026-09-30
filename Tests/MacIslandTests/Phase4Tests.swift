import AppKit
import Foundation
import ImageIO
import Testing
@testable import MacIsland

// MARK: Pomodoro

struct PomodoroHistoryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    @Test func streakCountsConsecutiveDaysEndingTodayOrYesterday() {
        var history = PomodoroHistory()
        history.record(on: day(-2), calendar: calendar)
        history.record(on: day(-1), calendar: calendar)
        // Nothing yet today: yesterday's streak is still alive.
        #expect(history.streak(asOf: day(0), calendar: calendar) == 2)
        history.record(on: day(0), calendar: calendar)
        history.record(on: day(0), calendar: calendar)
        #expect(history.streak(asOf: day(0), calendar: calendar) == 3)
        #expect(history.count(on: day(0), calendar: calendar) == 2)
    }

    @Test func aMissedDayBreaksTheStreak() {
        var history = PomodoroHistory()
        history.record(on: day(-3), calendar: calendar)
        history.record(on: day(-1), calendar: calendar)
        #expect(history.streak(asOf: day(0), calendar: calendar) == 1)
        #expect(PomodoroHistory().streak(asOf: day(0), calendar: calendar) == 0)
    }

    @Test func lastSevenDaysAreOldestFirstEndingToday() {
        var history = PomodoroHistory()
        history.record(on: day(0), calendar: calendar)
        history.record(on: day(-6), calendar: calendar)
        let days = history.lastSevenDays(asOf: day(0), calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first?.count == 1 && days.last?.count == 1)
        #expect(days[1].count == 0)
        #expect(days[0].date < days[6].date)
    }
}

@MainActor
struct PomodoroModelTests {
    private func makeModel() -> PomodoroModel {
        let defaults = UserDefaults(suiteName: "MacIslandPomodoro")!
        defaults.removePersistentDomain(forName: "MacIslandPomodoro")
        return PomodoroModel(defaults: defaults)
    }

    @Test func focusThenBreakThenFocus() {
        #expect(PomodoroModel.next(after: .focus, focusFinished: 1) == .shortBreak)
        #expect(PomodoroModel.next(after: .shortBreak, focusFinished: 1) == .focus)
        #expect(PomodoroModel.next(after: .focus, focusFinished: 4) == .longBreak)
        #expect(PomodoroModel.next(after: .longBreak, focusFinished: 4) == nil)
    }

    @Test func finishingFocusCreditsItAndChainsIntoABreak() {
        let model = makeModel()
        var ended: (PomodoroPhase, PomodoroPhase)?
        model.onPhaseEnd = { ended = ($0, $1) }
        model.toggle()
        model.advance(completed: true)
        #expect(model.phase == .shortBreak && model.isRunning)
        #expect(model.focusInCycle == 1)
        #expect(model.history.count(on: Date()) == 1)
        #expect(ended?.0 == .focus && ended?.1 == .shortBreak)
        model.reset()
    }

    @Test func skippingGivesNoCredit() {
        let model = makeModel()
        model.toggle()
        model.skip()
        #expect(model.phase == .shortBreak)
        #expect(model.focusInCycle == 0 && model.history.count(on: Date()) == 0)
        model.reset()
    }

    @Test func aFullCycleEndsAfterTheLongBreak() {
        let model = makeModel()
        model.toggle()
        // Four focus sessions, three short breaks, then the long break.
        for _ in 0..<7 { model.advance(completed: true) }
        #expect(model.phase == .longBreak)
        model.advance(completed: true)
        #expect(!model.isActive && model.phase == .focus && model.focusInCycle == 0)
        #expect(model.history.count(on: Date()) == 4)
    }

    @Test func historyPersists() {
        let defaults = UserDefaults(suiteName: "MacIslandPomodoro2")!
        defaults.removePersistentDomain(forName: "MacIslandPomodoro2")
        let first = PomodoroModel(defaults: defaults)
        first.toggle()
        first.advance(completed: true)
        first.reset()
        #expect(PomodoroModel(defaults: defaults).history.count(on: Date()) == 1)
    }

    @Test func pomodoroIsALiveActivityRankedAfterTheTimer() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.pomodoro.toggle()
        #expect(viewModel.compactActivity == .pomodoro)
        viewModel.timer.start(minutes: 5)
        #expect(viewModel.compactActivities == [.timer, .pomodoro])
        viewModel.timer.reset()
        viewModel.pomodoro.reset()
    }

    @Test func pomodoroModeAddsTheStatsToTheClockHeight() {
        let viewModel = TestSupport.makeViewModel()
        let plain = viewModel.contentHeight(for: .clock)
        viewModel.setClockMode(.pomodoro)
        #expect(viewModel.contentHeight(for: .clock) == plain + Theme.Metrics.pomodoroStatsHeight)
    }
}

// MARK: Home

struct MonthGridTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    @Test func septemberTwentyTwentySixStartsOnATuesday() {
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        let weeks = MonthGrid.weeks(containing: september, calendar: calendar)
        #expect(weeks.count == 6 && weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0] == [nil, nil, 1, 2, 3, 4, 5])
        #expect(weeks.flatMap { $0 }.compactMap { $0 }.count == 30)
    }

    @Test func weekdaysStartFromTheFirstWeekday() {
        var monday = calendar
        monday.firstWeekday = 2
        #expect(MonthGrid.weekdayInitials(calendar: monday).first == "M")
        #expect(MonthGrid.weekdayInitials(calendar: calendar).first == "S")
    }
}

@MainActor
struct WeatherTests {
    private let forecast = Data(#"{"current":{"temperature_2m":18.6,"weather_code":61,"is_day":0}}"#.utf8)
    private let place = Data(#"{"results":[{"name":"Paris","latitude":48.85,"longitude":2.35,"country":"France"}]}"#.utf8)

    @Test func requestsUseTheCityNameAndUnits() {
        #expect(WeatherModel.searchName(from: "Paris, France") == "Paris")
        #expect(WeatherModel.searchName(from: "  ") == "")
        let geocode = WeatherModel.geocodingURL(city: "New York")?.absoluteString
        #expect(geocode?.contains("name=New%20York") == true)
        let url = WeatherModel.forecastURL(place: .init(name: "Paris", latitude: 48.85, longitude: 2.35), fahrenheit: true)
        #expect(url?.absoluteString.contains("temperature_unit=fahrenheit") == true)
        #expect(url?.absoluteString.contains("latitude=48.85") == true)
    }

    @Test func parsesThePlaceAndTheConditions() {
        let parsed = WeatherModel.parsePlace(place)
        #expect(parsed == .init(name: "Paris", latitude: 48.85, longitude: 2.35))
        let conditions = WeatherModel.parseConditions(forecast, place: parsed!)
        #expect(conditions?.temperature == 19)
        #expect(conditions?.summary == "Rain")
        #expect(WeatherModel.parsePlace(Data(#"{"results":[]}"#.utf8)) == nil)
        #expect(WeatherModel.parseConditions(Data("nope".utf8), place: parsed!) == nil)
    }

    @Test func nightAndDayPickDifferentSymbols() {
        #expect(WeatherModel.describe(code: 0, isDay: true).symbol == "sun.max.fill")
        #expect(WeatherModel.describe(code: 0, isDay: false).symbol == "moon.stars.fill")
        #expect(WeatherModel.describe(code: 95, isDay: true).summary == "Thunderstorm")
    }

    @Test func followsTheCityAndClearsWhenItIsEmptied() async throws {
        let model = WeatherModel()
        model.typingPause = .zero
        model.refreshInterval = .seconds(3600)
        let place = place, forecast = forecast
        var requests: [String] = []
        model.fetch = { url in
            requests.append(url.host ?? "")
            return url.host == "geocoding-api.open-meteo.com" ? place : forecast
        }
        model.configure(city: "Paris")
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.conditions?.place == "Paris")
        #expect(requests == ["geocoding-api.open-meteo.com", "api.open-meteo.com"])
        model.configure(city: "")
        #expect(model.conditions == nil)
    }

    @Test func cityPersistsAndNotifies() {
        let defaults = UserDefaults(suiteName: "MacIslandWeatherCity")!
        defaults.removePersistentDomain(forName: "MacIslandWeatherCity")
        let settings = AppSettings(defaults: defaults)
        var notified = 0
        settings.onWeatherChange = { notified += 1 }
        settings.weatherCity = "Oslo"
        #expect(notified == 1)
        #expect(AppSettings(defaults: defaults).weatherCity == "Oslo")
    }
}

struct SystemStatsTests {
    @Test func cpuUsageIsBusyOverTotal() {
        let usage = SystemStats.cpuUsage(
            previous: .init(busy: 100, total: 1000), current: .init(busy: 300, total: 1400)
        )
        #expect(usage == 0.5)
        #expect(SystemStats.cpuUsage(previous: .init(busy: 5, total: 10), current: .init(busy: 5, total: 10)) == 0)
    }

    @Test func networkRateIgnoresCountersThatWentBackwards() {
        #expect(SystemStats.rate(from: 1000, to: 3000, over: 2) == 1000)
        #expect(SystemStats.rate(from: 3000, to: 1000, over: 2) == 0)
    }

    @Test func ratesAreReadable() {
        #expect(SystemStats.formatRate(0) == "0 B/s")
        #expect(SystemStats.formatRate(1_500) == "1.5 KB/s")
        #expect(SystemStats.formatRate(250_000) == "250 KB/s")
        #expect(SystemStats.formatRate(3_200_000) == "3.2 MB/s")
    }

    @Test func realReadingsAreSane() {
        let ticks = SystemStats.readCPUTicks()
        #expect(ticks.total > 0 && ticks.busy <= ticks.total)
        let memory = SystemStats.readMemoryFraction()
        #expect(memory > 0 && memory <= 1)
    }

    @MainActor
    @Test func sampleNeedsABaselineThenReports() {
        let stats = SystemStats()
        stats.sample()
        #expect(stats.snapshot == nil)
        stats.sample(now: Date().addingTimeInterval(2))
        #expect(stats.snapshot != nil)
        stats.reset()
        #expect(stats.snapshot == nil)
    }
}

// MARK: Shelf

struct SmartActionTests {
    @Test func linksAddressesAndColors() {
        #expect(SmartAction.detect(in: "https://example.com/a?b=1") == .openURL(URL(string: "https://example.com/a?b=1")!))
        #expect(SmartAction.detect(in: "  someone@example.com  ") == .email("someone@example.com"))
        #expect(SmartAction.detect(in: "#ff5733") == .color(hex: "#FF5733", rgb: "rgb(255, 87, 51)"))
        #expect(SmartAction.detect(in: "#fa0") == .color(hex: "#FFAA00", rgb: "rgb(255, 170, 0)"))
    }

    @Test func aSentenceThatContainsOneIsNotAnAction() {
        #expect(SmartAction.detect(in: "see https://example.com for details") == nil)
        #expect(SmartAction.detect(in: "mail me at someone@example.com") == nil)
        #expect(SmartAction.detect(in: "ff5733") == nil)
        #expect(SmartAction.detect(in: "#12345") == nil)
        #expect(SmartAction.detect(in: "ftp://example.com/file") == nil)
        #expect(SmartAction.detect(in: "line one\nhttps://example.com") == nil)
        #expect(SmartAction.detect(in: "") == nil)
    }

    @Test func actionsAreNamedForWhatTheyDo() {
        #expect(SmartAction.openURL(URL(string: "https://a.b")!).title == "Open")
        #expect(SmartAction.color(hex: "#000000", rgb: "rgb(0, 0, 0)").title == "Copy RGB")
        #expect(SmartAction.email("a@b.c").title == "New Email")
    }
}

struct FileToolsTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePNG(in directory: URL) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = directory.appendingPathComponent("picture.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    @Test func aFileZipsBareAndUnzipsBackBesideTheArchive() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("hello.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let archive = FileTools.uniqueURL(for: FileTools.zipDestination(for: [file]), in: directory)
        #expect(archive.lastPathComponent == "hello.txt.zip")
        _ = try FileTools.zip([file], to: archive)
        #expect(FileTools.isZip(archive))

        // The file is at the top of the archive, not inside the folder it was in.
        let out = directory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let restored = try FileTools.unzip(archive, into: out)
        #expect(restored.lastPathComponent == "hello.txt" && restored.deletingLastPathComponent().lastPathComponent == "out")
        #expect(try String(contentsOf: restored, encoding: .utf8) == "hello")
    }

    @Test func aFolderKeepsItsNameInTheArchive() throws {
        let directory = try makeDirectory()
        let folder = directory.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "a".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let archive = directory.appendingPathComponent("Project.zip")
        _ = try FileTools.zip([folder], to: archive)
        let out = directory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let restored = try FileTools.unzip(archive, into: out)
        #expect(restored.lastPathComponent == "Project")
        #expect(FileManager.default.fileExists(atPath: restored.appendingPathComponent("b.txt").path))
    }

    @Test func severalItemsOpenTogetherInAFolderNamedForTheArchive() throws {
        let directory = try makeDirectory()
        let urls = ["a.txt", "b.txt"].map { directory.appendingPathComponent($0) }
        for url in urls { try url.lastPathComponent.write(to: url, atomically: true, encoding: .utf8) }
        #expect(FileTools.zipDestination(for: urls) == "Archive.zip")

        let archive = directory.appendingPathComponent("Archive.zip")
        _ = try FileTools.zip(urls, to: archive)
        let out = directory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let restored = try FileTools.unzip(archive, into: out)
        #expect(restored.lastPathComponent == "Archive")
        let names = try FileManager.default.contentsOfDirectory(atPath: restored.path).sorted()
        #expect(names == ["a.txt", "b.txt"])
    }

    @Test func aFileIsNotGivenItsParentFolder() {
        let file = URL(fileURLWithPath: "/tmp/a.txt")
        #expect(!FileTools.zipArguments([file], to: URL(fileURLWithPath: "/tmp/a.zip"), keepParent: false).contains("--keepParent"))
        #expect(FileTools.zipArguments([file], to: URL(fileURLWithPath: "/tmp/a.zip"), keepParent: true).contains("--keepParent"))
    }

    @Test func namesNeverOverwrite() throws {
        let directory = try makeDirectory()
        try Data().write(to: directory.appendingPathComponent("a.zip"))
        #expect(FileTools.uniqueURL(for: "a.zip", in: directory).lastPathComponent == "a 2.zip")
        try Data().write(to: directory.appendingPathComponent("a 2.zip"))
        #expect(FileTools.uniqueURL(for: "a.zip", in: directory).lastPathComponent == "a 3.zip")
        #expect(FileTools.uniqueURL(for: "folder", in: directory).lastPathComponent == "folder")
    }

    @Test func convertsAnImageToOtherFormats() throws {
        let directory = try makeDirectory()
        let png = try makePNG(in: directory)
        for format in [ConversionTarget.jpeg, .tiff, .pdf] {
            let output = directory.appendingPathComponent("out.\(format.fileExtension)")
            _ = try Converters.image(at: png, to: format, destination: output)
            #expect(FileManager.default.fileExists(atPath: output.path))
            if format != .pdf {
                #expect(CGImageSourceCreateWithURL(output as CFURL, nil).flatMap(CGImageSourceGetType) as String? == format.type.identifier)
            }
        }
        #expect(throws: FileToolError.self) {
            try Converters.image(at: directory, to: .jpeg, destination: directory.appendingPathComponent("x.jpg"))
        }
    }

    @Test func offersOnlyOtherFormatsForImages() throws {
        let directory = try makeDirectory()
        let png = try makePNG(in: directory)
        let formats = ConversionTarget.targets(for: png)
        #expect(!formats.contains(.png) && formats.contains(.jpeg) && formats.contains(.pdf))
        #expect(ConversionTarget.targets(for: directory.appendingPathComponent("notes.txt")).contains(.pdf))
        #expect(ConversionTarget.targets(for: directory.appendingPathComponent("archive.zip")).isEmpty)
    }
}

@MainActor
struct WorkTrackerTests {
    @Test func aJobIsALiveActivityUntilItEnds() {
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.compactActivity == .none)
        let id = viewModel.work.begin("Zipping")
        #expect(viewModel.compactActivity == .working("Zipping"))
        viewModel.work.end(id)
        #expect(viewModel.compactActivity == .none)
    }

    @Test func workRanksBelowTheStopwatchAndAboveDownloads() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.stopwatch.toggle()
        let id = viewModel.work.begin("Converting")
        #expect(viewModel.compactActivities == [.stopwatch, .working("Converting")])
        viewModel.work.end(id)
        viewModel.stopwatch.reset()
    }
}

// MARK: Notes

@MainActor
struct NotesModelTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func notesAreNamedByTheirFirstLine() {
        #expect(Note(body: "Groceries\nmilk").title == "Groceries")
        #expect(Note(body: "\n\n").title == "New Note")
        #expect(Note(body: String(repeating: "x", count: 100)).title.count == 60)
    }

    @Test func notesAndSnippetsPersistAcrossLaunches() {
        let directory = makeDirectory()
        let model = NotesModel(directory: directory)
        let note = model.addNote()
        model.setBody("Call Sam", ofNote: note.id)
        let snippet = model.addSnippet()
        model.setTitle("Sign-off", ofSnippet: snippet.id)
        model.setText("Best,\nEthan", ofSnippet: snippet.id)
        model.save()

        let reloaded = NotesModel(directory: directory)
        #expect(reloaded.notes.map(\.body) == ["Call Sam"])
        #expect(reloaded.snippets.first?.text == "Best,\nEthan")
        #expect(reloaded.selectedNoteID == note.id)
    }

    @Test func deletingMovesTheSelectionToANeighbor() {
        let model = NotesModel(directory: makeDirectory())
        let first = model.addNote()
        let second = model.addNote()
        #expect(model.selectedNoteID == second.id)
        model.deleteNote(second.id)
        #expect(model.selectedNoteID == first.id)
        model.deleteNote(first.id)
        #expect(model.selectedNoteID == nil && model.notes.isEmpty)
    }

    @Test func savesAfterAPauseInTyping() async throws {
        let directory = makeDirectory()
        let model = NotesModel(directory: directory)
        let note = model.addNote()
        model.setBody("typed", ofNote: note.id)
        try await Task.sleep(for: .milliseconds(800))
        #expect(NotesModel(directory: directory).notes.first?.body == "typed")
    }

    @Test func notesIsAModuleYouCanAddToTheStrip() {
        #expect(IslandModule.notes.isAvailable)
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.contentHeight(for: .notes) == Theme.Metrics.notesHeight)
    }
}

// MARK: Tools

@MainActor
struct CleanKeyboardTests {
    @Test func itSwallowsKeysAndMediaKeysNotTheMouse() {
        let types = KeyboardCleaner.swallowedTypes
        #expect(types.contains(.keyDown) && types.contains(.keyUp) && types.contains(.flagsChanged))
        #expect(!types.contains(.leftMouseDown) && !types.contains(.mouseMoved))
    }

    @Test func startsUnlockedAndUnlockingIsSafeAnytime() {
        let cleaner = KeyboardCleaner()
        #expect(!cleaner.isLocked)
        cleaner.unlock()
        #expect(!cleaner.isLocked)
    }

    @Test func toolsGridHoldsEveryToolInTwoRowsOfFive() {
        #expect(ToolID.allCases.count == 9)
        #expect(ToolID.allCases.count + 1 <= 2 * 5)
        let defaults = UserDefaults(suiteName: "MacIslandTools8")!
        defaults.removePersistentDomain(forName: "MacIslandTools8")
        let settings = AppSettings(defaults: defaults)
        settings.pinLimit = .eight
        // Nine tools no longer fit the widest row, so the row keeps its More button.
        #expect(!settings.rowShowsEveryTool && settings.visiblePinned.count == 8)
    }
}

@MainActor
struct QuickNoteTests {
    @Test func theStripPencilStartsANoteOnTheNotesTab() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.setNotesMode(.prompter)
        viewModel.openQuickNote()
        #expect(viewModel.selectedTab == .notes)
        #expect(viewModel.notesMode == .notes)
        #expect(viewModel.notes.notes.count == 1)
        #expect(viewModel.notes.selectedNoteID == viewModel.notes.notes.first?.id)
    }
}

// MARK: Reminders, Home, and the strip

struct ReminderRowTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000 + 12 * 3600)

    private func row(_ title: String, after hours: Double?, hasTime: Bool = true) -> ReminderRow {
        ReminderRow(id: title, title: title, due: hours.map { now.addingTimeInterval($0 * 3600) }, hasTime: hasTime)
    }

    @Test func datedFirstSoonestOnTopThenUndated() {
        let sorted = ReminderRow.sorted([row("none", after: nil), row("later", after: 30), row("overdue", after: -5), row("soon", after: 2)])
        #expect(sorted.map(\.title) == ["overdue", "soon", "later", "none"])
    }

    @Test func dueTextIsShortAndHuman() {
        #expect(row("a", after: -1).dueText(now: now, calendar: calendar) == "Overdue")
        #expect(row("b", after: 2).dueText(now: now, calendar: calendar).contains(":"))
        #expect(row("c", after: 24 + 1).dueText(now: now, calendar: calendar) == "Tomorrow")
        #expect(row("d", after: nil).dueText(now: now, calendar: calendar).isEmpty)
        // A date without a time is "Today" all day, and overdue only once the day has passed.
        #expect(row("e", after: 0, hasTime: false).dueText(now: now, calendar: calendar) == "Today")
        #expect(row("f", after: -24, hasTime: false).dueText(now: now, calendar: calendar) == "Overdue")
    }
}

@MainActor
struct RemindersTabTests {
    @Test func remindersIsATabWithItsOwnHeight() {
        #expect(IslandModule.reminders.isAvailable)
        #expect(IslandModule.defaultTabs == [.home, .media, .clock, .reminders, .tools])
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.contentHeight(for: .reminders) == Theme.Metrics.remindersHeight)
        // The order is the one chosen, not the module order.
        #expect(AppSettings.normalized([.tools, .reminders, .home]) == [.tools, .reminders, .home])
    }

    @Test func anUnchangedStripMovesToTheNewDefaultButACustomOneStays() {
        let defaults = UserDefaults(suiteName: "MacIslandTabsMigration")!
        defaults.removePersistentDomain(forName: "MacIslandTabsMigration")
        defaults.set(IslandModule.previousDefaultTabs.map(\.rawValue), forKey: "tabs")
        #expect(AppSettings(defaults: defaults).tabs == IslandModule.defaultTabs)

        defaults.set([IslandModule.home, .shelf].map(\.rawValue), forKey: "tabs")
        #expect(AppSettings(defaults: defaults).tabs == [.home, .shelf])
    }
}

@MainActor
struct HomeAndPeekTests {
    @Test func theStripWeatherStepsAsideForLiveStatus() async throws {
        let viewModel = TestSupport.makeViewModel()
        let weather = viewModel.weather
        weather.typingPause = .zero
        weather.fetch = { url in
            url.host == "geocoding-api.open-meteo.com"
                ? Data(#"{"results":[{"name":"Paris","latitude":1,"longitude":2}]}"#.utf8)
                : Data(#"{"current":{"temperature_2m":10,"weather_code":0,"is_day":1}}"#.utf8)
        }
        weather.configure(city: "Paris")
        try await Task.sleep(for: .milliseconds(150))
        viewModel.selectedTab = .home
        #expect(viewModel.showsStripWeather)

        viewModel.timer.start(minutes: 5)
        #expect(viewModel.hasStatusIndicators && !viewModel.showsStripWeather)
        // On the Clock tab the ring already says it, so nothing is added to the strip.
        viewModel.selectedTab = .clock
        #expect(!viewModel.hasStatusIndicators && viewModel.showsStripWeather)
        viewModel.timer.reset()
        weather.configure(city: "")
    }

    @Test func thereIsNoWeatherToShowWithoutACity() {
        let viewModel = TestSupport.makeViewModel()
        #expect(!viewModel.showsStripWeather)
    }

    @Test func theIdlePeekIsTallerThanAGlanceButTimersAndMusicKeepTheirSize() {
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.peekContentHeight == Theme.Metrics.idlePeekHeight)
        viewModel.timer.start(minutes: 5)
        #expect(viewModel.peekContentHeight == Theme.Metrics.glanceHeight)
        viewModel.timer.reset()
    }

    @Test func homeHasOneHeightClosedAndAnotherWithTheCalendar() {
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.contentHeight(for: .home) == Theme.Metrics.homeContentHeight)
        viewModel.setCalendarExpanded(true)
        #expect(viewModel.contentHeight(for: .home) == Theme.Metrics.homeMonthHeight)
        // Everything fits in the panel below the notch.
        let room = ScreenGeometry.panelSize.height - viewModel.geometry.notchSize.height - Theme.Metrics.contentTopGap - Theme.Metrics.margin
        #expect(Theme.Metrics.homeMonthHeight <= room && Theme.Metrics.remindersHeight <= room && Theme.Metrics.notesHeight <= room)
    }

    @Test func openingTheClockFromHomePicksTheRunningMode() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.openClock(.pomodoro)
        #expect(viewModel.selectedTab == .clock && viewModel.clockMode == .pomodoro)
    }

    @Test func batteryGlyphMatchesTheLevel() {
        #expect(BatteryMonitor.symbol(percent: 100, onAC: false) == "battery.100percent")
        #expect(BatteryMonitor.symbol(percent: 100, onAC: true) == "battery.100percent.bolt")
        #expect(BatteryMonitor.symbol(percent: 55, onAC: false) == "battery.50percent")
        #expect(BatteryMonitor.symbol(percent: 8, onAC: false) == "battery.0percent")
    }
}

@MainActor
struct TimerPeekTests {
    @Test func addingMinutesExtendsARunningTimerAndShowsWhenItEnds() {
        let timer = TimerModel()
        timer.start(minutes: 5)
        let before = timer.endDate
        #expect(before != nil)
        timer.add(minutes: 5)
        #expect(timer.duration == 10 * 60)
        #expect((timer.endDate ?? .distantPast).timeIntervalSince(before ?? .distantFuture) > 299)
        timer.toggle()
        #expect(timer.endDate == nil)
        timer.reset()
    }
}


// MARK: Home layout and Settings wording

@MainActor
struct HomeWidgetsTests {
    @Test func theActionPillOffersTimersThenPomodoroThenShelf() {
        let idle = HomeAction.list(timerActive: false, pomodoroActive: false, stopwatchActive: false, shelfCount: 0)
        #expect(idle == [.timer(minutes: 5), .timer(minutes: 25), .pomodoro, .shelf(count: 0)])
    }

    @Test func aRunningClockTakesItsSegmentsPlace() {
        let timer = HomeAction.list(timerActive: true, pomodoroActive: false, stopwatchActive: false, shelfCount: 2)
        #expect(timer == [.runningTimer, .pomodoro, .shelf(count: 2)])
        let all = HomeAction.list(timerActive: true, pomodoroActive: true, stopwatchActive: true, shelfCount: 0)
        #expect(all == [.runningTimer, .runningPomodoro, .runningStopwatch, .shelf(count: 0)])
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func cornersStepDownFromTheIslandToItsWidgetsToWhatIsInsideThem() {
        #expect(Theme.Metrics.expandedRadius > Theme.Metrics.widgetRadius)
        #expect(Theme.Metrics.widgetRadius > Theme.Metrics.nestedRadius)
        // Concentric: the island's radius less the margin it leaves around a widget.
        #expect(Theme.Metrics.widgetRadius == Theme.Metrics.expandedRadius - Theme.Metrics.margin)
    }

    @Test func homeFitsBelowTheNotch() {
        let viewModel = TestSupport.makeViewModel()
        let room = ScreenGeometry.panelSize.height - viewModel.geometry.notchSize.height - Theme.Metrics.contentTopGap - Theme.Metrics.margin
        #expect(Theme.Metrics.homeContentHeight == Theme.Metrics.homeCardHeight + Theme.Metrics.homeActionsHeight + 10)
        #expect(Theme.Metrics.homeContentHeight <= room)
    }
}

@MainActor
struct SettingsWordingTests {
    @Test func modulesOutsideTheStripSayHowElseTheyOpen() {
        #expect(IslandModule.notes.otherWayIn?.contains("pencil") == true)
        #expect(IslandModule.shelf.otherWayIn?.contains("drop") == true)
        #expect(IslandModule.reminders.otherWayIn == nil)
    }

    @Test func theStripCountTracksTheSettings() {
        let defaults = UserDefaults(suiteName: "MacIslandStripCount")!
        defaults.removePersistentDomain(forName: "MacIslandStripCount")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.tabs.count == Theme.Metrics.maxTabs && !settings.hasRoom(on: .left))
        settings.toggleTab(.tools)
        #expect(settings.tabs.count == Theme.Metrics.maxTabs - 1 && settings.hasRoom(on: .left))
        settings.toggleTab(.notes)
        #expect(settings.isInTabs(.notes) && !settings.hasRoom(on: .left))
    }
}

// MARK: Two sides of tabs

@MainActor
struct TabSidesTests {
    private func makeSettings(_ name: String = "MacIslandTabSides") -> (AppSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppSettings(defaults: defaults), defaults)
    }

    @Test func fiveOnTheLeftAndOneOnTheRight() {
        #expect(Theme.Metrics.maxTabs == 5 && Theme.Metrics.maxRightTabs == 1)
        let (settings, _) = makeSettings()
        #expect(settings.leftTabs.count == 5 && settings.rightTabs.isEmpty)
        #expect(settings.hasRoom(on: .right) && !settings.hasRoom(on: .left))
    }

    @Test func turningOnWithALeftSideFullUsesTheRightThenRefuses() {
        let (settings, _) = makeSettings()
        settings.setEnabled(.notes, true)
        #expect(settings.side(of: .notes) == .right)
        settings.setEnabled(.shelf, true)
        #expect(!settings.isInTabs(.shelf) && !settings.canAddTab)
        settings.setEnabled(.notes, false)
        #expect(!settings.isInTabs(.notes) && settings.canAddTab)
    }

    @Test func movingBetweenSidesRespectsCapacity() {
        let (settings, _) = makeSettings()
        #expect(settings.move(.tools, to: .right))
        #expect(settings.side(of: .tools) == .right && settings.leftTabs.count == 4)
        // The right side holds one, so another can't join it; the left has room again.
        #expect(!settings.move(.clock, to: .right))
        #expect(settings.side(of: .clock) == .left)
        #expect(settings.move(.notes, to: .left))
        #expect(settings.leftTabs.last == .notes)
        #expect(!settings.move(.shelf, to: .left))
    }

    @Test func droppingBeforeATabReordersIt() {
        let (settings, _) = makeSettings()
        #expect(settings.move(.tools, to: .left, before: .home))
        #expect(settings.leftTabs.first == .tools)
        #expect(Set(settings.leftTabs).count == settings.leftTabs.count)
        #expect(!settings.move(.tools, to: .left, before: .tools))
    }

    @Test func nudgeStaysWithinItsSide() {
        let (settings, _) = makeSettings()
        settings.nudge(.home, by: -1)
        #expect(settings.leftTabs.first == .home)
        settings.nudge(.home, by: 1)
        #expect(settings.leftTabs[1] == .home)
    }

    @Test func theLastTabCannotBeTurnedOff() {
        let (settings, _) = makeSettings()
        for module in settings.tabs.dropLast() { settings.setEnabled(module, false) }
        #expect(settings.tabs.count == 1)
        settings.setEnabled(settings.tabs[0], false)
        #expect(settings.tabs.count == 1)
    }

    @Test func bothSidesPersistInOrder() {
        let (settings, defaults) = makeSettings("MacIslandTabSidesPersist")
        settings.move(.tools, to: .right)
        settings.move(.home, to: .left, before: nil)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.leftTabs == settings.leftTabs && reloaded.rightTabs == [.tools])
        #expect(reloaded.leftTabs.last == .home)
    }

    @Test func aModuleNeverAppearsOnBothSides() {
        let (left, right) = AppSettings.normalized(left: [.home, .media], right: [.media, .clock, .tools])
        #expect(left == [.home, .media])
        #expect(right == [.clock])
        let (emptyLeft, emptyRight) = AppSettings.normalized(left: [], right: [])
        #expect(emptyLeft == IslandModule.defaultTabs && emptyRight.isEmpty)
    }

    @Test func theOldSingleListBecomesTheLeftSide() {
        let defaults = UserDefaults(suiteName: "MacIslandTabsLegacy")!
        defaults.removePersistentDomain(forName: "MacIslandTabsLegacy")
        defaults.set(["home", "notes", "tools"], forKey: "tabs")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.leftTabs == [.home, .notes, .tools] && settings.rightTabs.isEmpty)
    }

    @Test func hiddenModulesAreTheOnesNotShown() {
        let (settings, _) = makeSettings()
        #expect(settings.hiddenModules.contains(.shelf) && settings.hiddenModules.contains(.notes))
        #expect(!settings.hiddenModules.contains(.home))
        #expect(!settings.hiddenModules.contains(.agents))
    }
}

struct TrailingStripTests {
    @Test func roomForEverythingWithNothingLive() {
        let plan = TrailingStrip.plan(available: 154, rightTabs: 0, hasStatus: false, hasWeather: true)
        #expect(plan == .init(weather: true, pencil: true))
    }

    @Test func aRightTabKeepsTheWeatherAndDropsThePencilBeforeIt() {
        // The tab, the weather, and Settings fit; the pencil would not.
        let plan = TrailingStrip.plan(available: 154, rightTabs: 1, hasStatus: false, hasWeather: true)
        #expect(plan == .init(weather: true, pencil: false))
    }

    @Test func aClockAndATabPushTheWeatherAndPencilOut() {
        let plan = TrailingStrip.plan(available: 154, rightTabs: 1, hasStatus: true, hasWeather: true)
        #expect(plan == .init(weather: false, pencil: false))
        // Without weather to show, the pencil still gets the room.
        #expect(TrailingStrip.plan(available: 154, rightTabs: 1, hasStatus: false, hasWeather: false).pencil)
    }

    @Test func thePencilIsLeftOutWhenNotesIsAlreadyATab() {
        let plan = TrailingStrip.plan(available: 154, rightTabs: 0, hasStatus: false, hasWeather: true, hasNotesTab: true)
        #expect(plan == .init(weather: true, pencil: false))
    }

    @Test func thePencilIsLastToAppear() {
        let plan = TrailingStrip.plan(available: 110, rightTabs: 0, hasStatus: false, hasWeather: true)
        #expect(plan == .init(weather: true, pencil: false))
    }

    @Test func whateverIsShownAlwaysFits() {
        for tabs in 0...1 {
            for status in [false, true] {
                for notes in [false, true] {
                    let available: CGFloat = 154
                    let plan = TrailingStrip.plan(
                        available: available, rightTabs: tabs, hasStatus: status, hasWeather: true, hasNotesTab: notes
                    )
                    var used = TrailingStrip.settings + CGFloat(tabs) * (TrailingStrip.tab + TrailingStrip.spacing)
                    if status { used += TrailingStrip.status + TrailingStrip.spacing }
                    if plan.weather { used += TrailingStrip.weather + TrailingStrip.spacing }
                    if plan.pencil { used += TrailingStrip.pencil + TrailingStrip.spacing }
                    #expect(used <= available)
                }
            }
        }
    }
}

@MainActor
struct StripWeatherAndNotesTests {
    @Test func notesAsATabHidesThePencil() {
        let viewModel = TestSupport.makeViewModel()
        #expect(viewModel.showsStripPencil)
        viewModel.settings.move(.notes, to: .right)
        #expect(!viewModel.showsStripPencil)
        viewModel.settings.setEnabled(.notes, false)
        #expect(viewModel.showsStripPencil)
    }
}
