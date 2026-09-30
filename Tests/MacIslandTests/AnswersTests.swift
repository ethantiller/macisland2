import AppKit
import Foundation
import Testing
@testable import MacIsland

struct DictionaryTextTests {
    @Test func takesTheFirstSenseOnOneLine() {
        let entry = "serendipity | ˌserənˈdipitē | noun [mass noun] the occurrence and development of events by chance in a happy or beneficial way: a fortunate stroke of serendipity. ORIGIN 1754: coined by Horace Walpole"
        #expect(DictionaryText.firstSense(entry) == "the occurrence and development of events by chance in a happy or beneficial way")
    }

    @Test func skipsTheFormsBracketsAndNumberOfAVerb() {
        let entry = "run | rən | verb (runs, running; past ran) [no object] 1 move at a speed faster than a walk: she ran down the street. 2 operate"
        #expect(DictionaryText.firstSense(entry) == "move at a speed faster than a walk")
    }

    @Test func readsTheEntriesTheDictionaryReallyReturns() {
        let verb = "run | rən | verb (runs) (, running | ˈrəniNG |) (past; ran | ran |) (past participle; run | rən |) 1 [no object] move at a speed faster than a walk, never having both feet on the ground: the dog ran across the road | she ran the last mile"
        #expect(DictionaryText.firstSense(verb) == "move at a speed faster than a walk, never having both feet on the ground")
        let noun = "cat 1 | kat | noun 1 a small domesticated carnivorous mammal with soft fur, a short snout, and retractable claws. It is widely kept as a pet."
        #expect(DictionaryText.firstSense(noun) == "a small domesticated carnivorous mammal with soft fur, a short snout, and retractable claws")
        #expect(DictionaryText.firstSense("verb | vərb | noun a word that describes an action: to run") == "a word that describes an action")
    }

    @Test func aBareDefinitionIsKept() {
        #expect(DictionaryText.firstSense("a small domesticated carnivorous mammal.") == "a small domesticated carnivorous mammal")
        #expect(DictionaryText.firstSense("  ") == nil)
    }

    @Test func longSensesAreShortened() {
        let long = String(repeating: "word ", count: 60)
        #expect(DictionaryText.firstSense(long)!.count <= 120)
    }
}

struct UnitConversionTests {
    private func parse(_ text: String) -> UnitConversion.Request? { UnitConversion.parse(text) }

    @Test func parsesTheCommonForms() {
        let miles = parse("5 km in mi")
        #expect(miles?.value == 5 && miles?.from.symbol == "km" && miles?.to.symbol == "mi")
        #expect(parse("72f to c")?.from.symbol == "°F")
        #expect(parse("72°F to C")?.to.symbol == "°C")
        #expect(parse("8 fl oz in ml")?.from.symbol == "fl oz")
        #expect(parse("1,5 kg to lb")?.value == 1.5)
        #expect(parse("1 in to cm")?.from.symbol == "in")
        #expect(parse("60 mph in kph")?.to.symbol == "km/h")
        #expect(parse("2 gb to mb")?.to.symbol == "MB")
    }

    @Test func differentKindsOfUnitDoNotConvert() {
        #expect(parse("5 km in kg") == nil)
        #expect(parse("5 km in") == nil)
        #expect(parse("hello world") == nil)
        #expect(parse("100 usd in eur") == nil)
    }

    @Test func convertsAndFormats() throws {
        let miles = try #require(parse("5 km in mi"))
        #expect(UnitConversion.format(miles, locale: Locale(identifier: "en_US")) == "3.11 mi")
        let temperature = try #require(parse("212f to c"))
        #expect(UnitConversion.format(temperature, locale: Locale(identifier: "en_US")) == "100°C")
        let small = try #require(parse("1 mm in km"))
        #expect(UnitConversion.format(small, locale: Locale(identifier: "en_US")) == "0.000001 km")
    }
}

struct CalculatorTests {
    @Test func followsPrecedenceAndBrackets() {
        #expect(Calculator.evaluate("2*(3+4)") == 14)
        #expect(Calculator.evaluate("2+3*4") == 14)
        #expect(Calculator.evaluate("(2+3)*4") == 20)
        #expect(Calculator.evaluate("10/4") == 2.5)
        #expect(Calculator.evaluate("2^3^2") == 512)
        #expect(Calculator.evaluate("-3+5") == 2)
        #expect(Calculator.evaluate("2 × 3 ÷ 4") == 1.5)
        #expect(Calculator.evaluate("1.5 * 2") == 3)
    }

    @Test func badInputIsNilAndNeverCrashes() {
        for text in ["", "42", "2+", "(2+3", "2+3)", "abc", "1/0", "2**3", "1..2+1", String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500), String(repeating: "-", count: 5000) + "1"] {
            #expect(Calculator.evaluate(text) == nil, "\(text.prefix(20))")
        }
    }

    @Test func formatsWholeNumbersWithoutADecimalPoint() {
        #expect(Calculator.format(14) == "14")
        #expect(Calculator.format(2.5) == "2.5")
        #expect(Calculator.format(1.0 / 3.0) == "0.3333333333")
    }
}

struct CurrencyRequestTests {
    @Test func parsesCodesAndSymbols() {
        #expect(CurrencyRequest.parse("100 usd in eur") == CurrencyRequest(amount: 100, from: "USD", to: "EUR"))
        #expect(CurrencyRequest.parse("€50 to $") == CurrencyRequest(amount: 50, from: "EUR", to: "USD"))
        #expect(CurrencyRequest.parse("$20 in gbp") == CurrencyRequest(amount: 20, from: "USD", to: "GBP"))
        #expect(CurrencyRequest.parse("1,000.50 EUR to JPY")?.amount == 1000.5)
        #expect(CurrencyRequest.parse("12,5 eur to usd")?.amount == 12.5)
    }

    @Test func rejectsWhatIsNotACurrencyPair() {
        #expect(CurrencyRequest.parse("100 usd in usd") == nil)
        #expect(CurrencyRequest.parse("100 abc in eur") == nil)
        #expect(CurrencyRequest.parse("100 usd") == nil)
        #expect(CurrencyRequest.parse("5 km in mi") == nil)
    }

    @Test func formatsInTheTargetCurrency() {
        #expect(CurrencyRequest.format(92.1, code: "EUR", locale: Locale(identifier: "en_US")) == "€92.10")
    }
}

/// Counts fetches from a `@Sendable` closure.
private final class FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}

@MainActor
struct ExchangeRatesTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    @Test func fetchesOnceThenAgainAfterTwelveHours() async {
        let counter = FetchCounter()
        let clock = Clock()
        let rates = ExchangeRates(
            fetch: { _ in counter.bump(); return (["EUR": 0.9], Date(timeIntervalSince1970: 999_000)) },
            now: { clock.now }
        )
        #expect(rates.rate(from: "USD", to: "EUR") == nil)
        await rates.load(base: "USD")
        await rates.load(base: "USD")
        #expect(counter.value == 1)
        #expect(rates.rate(from: "USD", to: "EUR")?.value == 0.9)

        clock.now += 11 * 3600
        await rates.load(base: "USD")
        #expect(counter.value == 1)
        clock.now += 2 * 3600
        await rates.load(base: "USD")
        #expect(counter.value == 2)
    }

    @Test func eachBaseIsCachedApartAndAFailureLeavesNothing() async {
        let counter = FetchCounter()
        let rates = ExchangeRates(fetch: { base in
            counter.bump()
            if base == "GBP" { throw URLError(.notConnectedToInternet) }
            return (["EUR": 1.1], Date())
        })
        await rates.load(base: "USD")
        await rates.load(base: "GBP")
        #expect(rates.hasRates(for: "USD") && !rates.hasRates(for: "GBP"))
        #expect(rates.rate(from: "GBP", to: "EUR") == nil)
        #expect(rates.rate(from: "USD", to: "USD")?.value == 1)
    }

    @Test func parsesTheFrankfurterResponse() throws {
        let json = #"{"amount":1.0,"base":"USD","date":"2026-09-29","rates":{"EUR":0.88067,"GBP":0.75489}}"#
        let parsed = try #require(ExchangeRates.parse(Data(json.utf8)))
        #expect(parsed.rates["EUR"] == 0.88067)
        #expect(Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: parsed.date).day == 29)
        #expect(ExchangeRates.parse(Data("{}".utf8)) == nil)
        #expect(ExchangeRates.url(base: "USD")?.absoluteString == "https://api.frankfurter.dev/v1/latest?base=USD")
    }
}

private struct StubDictionary: DictionaryLookup {
    var entries: [String: String] = [:]
    func definition(of term: String) -> String? { entries[term] }
}

@MainActor
struct PaletteAnswerTests {
    @Test func defineShowsTheFirstSense() {
        let viewModel = TestSupport.makeViewModel()
        let palette = PaletteModel(viewModel: viewModel, dictionary: StubDictionary(entries: ["cat": "cat | kat | noun a small carnivorous mammal: a pet"]))
        palette.query = "define cat"
        #expect(palette.results.first?.title == "cat" && palette.results.first?.subtitle == "a small carnivorous mammal")
        palette.query = "def zzz"
        #expect(palette.results.first?.subtitle == "Look Up in Dictionary")
        #expect(PaletteModel.definitionTerm(from: "define  ") == nil)
        #expect(PaletteModel.definitionTerm(from: "definite") == nil)
    }

    @Test func unitsAndSumsAreAnswersThatCopy() {
        let viewModel = TestSupport.makeViewModel()
        let palette = PaletteModel(viewModel: viewModel)
        palette.query = "5 km in mi"
        #expect(palette.results.first?.subtitle == "Units")
        palette.query = "2*(3+4)"
        #expect(palette.results.first?.title == "= 14" && palette.results.first?.subtitle == "Calculator")
        palette.query = "25m"
        #expect(palette.results.first?.id == "timer")
    }

    @Test func aCurrencyRowWorksThenBecomesTheAnswer() async {
        let rates = ExchangeRates(fetch: { _ in (["EUR": 0.5], Date()) })
        let viewModel = TestSupport.makeViewModel(rates: rates)
        let palette = PaletteModel(viewModel: viewModel)
        palette.query = "100 usd in eur"
        #expect(palette.results.first?.id == "currency" && palette.results.first?.title == "Converting\u{2026}")
        for _ in 0..<50 where palette.results.first?.title == "Converting\u{2026}" { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(palette.results.first?.title.contains("50") == true)
        #expect(palette.results.first?.subtitle?.hasPrefix("Currency") == true)
    }

    @Test func aFailedCurrencyFetchOffersToTryAgain() async {
        let viewModel = TestSupport.makeViewModel(rates: ExchangeRates(fetch: { _ in throw URLError(.notConnectedToInternet) }))
        let palette = PaletteModel(viewModel: viewModel)
        palette.query = "100 usd in eur"
        for _ in 0..<50 where palette.results.first?.title == "Converting\u{2026}" { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(palette.results.first?.title.hasPrefix("Couldn") == true)
    }
}

@MainActor
struct URLCommandTests {
    private func parse(_ text: String) -> URLCommand? { URLCommand.parse(URL(string: text)!) }

    @Test func parsesEachCommand() throws {
        #expect(parse("macisland://timer?minutes=5") == .timer(minutes: 5))
        #expect(parse("macisland://stopwatch") == .stopwatch)
        #expect(parse("macisland://pomodoro") == .pomodoro)
        #expect(parse("macisland://palette") == .palette)
        #expect(parse("macisland://open?module=notes") == .open(.notes))
        #expect(parse("macisland://banner?title=Hi&detail=There&symbol=bell.fill") == .banner(title: "Hi", detail: "There", symbol: "bell.fill"))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let encoded = file.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        #expect(parse("macisland://shelf/add?path=\(encoded)") == .addToShelf(file.standardizedFileURL))
    }

    @Test func enforcesTheLimits() {
        #expect(parse("macisland://timer?minutes=0") == nil)
        #expect(parse("macisland://timer?minutes=99999") == nil)
        #expect(parse("macisland://timer") == nil)
        #expect(parse("macisland://open?module=agents") == nil)
        #expect(parse("macisland://open?module=nope") == nil)
        #expect(parse("macisland://shelf/add?path=/no/such/file") == nil)
        #expect(parse("macisland://shelf/add?path=relative.txt") == nil)
        #expect(parse("macisland://banner") == nil)
        #expect(parse("macisland://frobnicate") == nil)
        #expect(parse("https://timer?minutes=5") == nil)

        let longTitle = String(repeating: "t", count: 200), longDetail = String(repeating: "d", count: 200)
        guard case .banner(let title, let detail, let symbol) = parse("macisland://banner?title=\(longTitle)&detail=\(longDetail)&symbol=Not%20A%20Symbol!") else {
            Issue.record("expected a banner")
            return
        }
        #expect(title.count == 60 && detail?.count == 80 && symbol == nil)
    }

    @Test func bannersAreRateLimited() {
        let viewModel = TestSupport.makeViewModel()
        var now = Date(timeIntervalSince1970: 5_000)
        let runner = URLCommandRunner(viewModel: viewModel, openPalette: {}, now: { now })
        runner.run(.banner(title: "First", detail: nil, symbol: nil))
        #expect(viewModel.banner?.title == "First")
        now += 1
        runner.run(.banner(title: "Second", detail: nil, symbol: nil))
        #expect(viewModel.banner?.title == "First")
        now += 1.5
        runner.run(.banner(title: "Third", detail: nil, symbol: "not.a.real.symbol.name"))
        #expect(viewModel.banner?.title == "Third" && viewModel.banner?.systemImage == "bell.fill")
        #expect(viewModel.banner?.action == nil)
    }

    @Test func commandsDriveTheApp() {
        let viewModel = TestSupport.makeViewModel()
        var palettes = 0
        let runner = URLCommandRunner(viewModel: viewModel, openPalette: { palettes += 1 })
        runner.handle([URL(string: "macisland://timer?minutes=3")!, URL(string: "macisland://palette")!, URL(string: "macisland://open?module=tools")!])
        #expect(viewModel.timer.duration == 180 && palettes == 1 && viewModel.selectedTab == .tools)
        runner.run(.stopwatch)
        #expect(viewModel.stopwatch.isRunning)
        runner.run(.pomodoro)
        #expect(viewModel.pomodoro.isActive)
    }
}

@MainActor
struct LockScreenTests {
    @Test func postsControlCommandQ() {
        var events: [CGEvent] = []
        #expect(SystemActions.lockScreen(hasAccess: true) { events.append($0) })
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 12 })
        #expect(events.allSatisfy { $0.flags.contains(.maskControl) && $0.flags.contains(.maskCommand) })
        #expect(events.map(\.type) == [.keyDown, .keyUp])
    }

    @Test func withoutAccessNothingIsPosted() {
        var posted = 0
        #expect(!SystemActions.lockScreen(hasAccess: false) { _ in posted += 1 })
        #expect(posted == 0)
    }

    @Test func lockScreenIsATool() {
        #expect(ToolID.allCases.contains(.lockScreen))
        let tool = ToolCatalog(viewModel: TestSupport.makeViewModel()).item(for: .lockScreen)
        #expect(tool.title == "Lock Screen" && tool.systemImage == "lock.fill")
        // Nine tools and Less fill the 5 x 2 grid.
        #expect(ToolID.allCases.count + 1 == 10)
    }
}
