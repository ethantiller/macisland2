import CoreServices
import Foundation

// MARK: Define

protocol DictionaryLookup: Sendable {
    func definition(of term: String) -> String?
}

/// The Dictionary app's own entries, through DictionaryServices.
struct SystemDictionary: DictionaryLookup {
    func definition(of term: String) -> String? {
        let range = CFRange(location: 0, length: (term as NSString).length)
        return DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String?
    }
}

enum DictionaryText {
    private nonisolated static let partsOfSpeech =
        #"\b(?:noun|verb|adjective|adverb|pronoun|preposition|conjunction|exclamation|determiner|abbreviation|prefix|suffix|symbol|interjection|numeral|modal verb|auxiliary verb)\b\s*"#
    /// What can sit between the part of speech and the meaning: forms in brackets, notes, and sense numbers.
    private nonisolated static let leading = #"^(?:\[[^\]]*\]\s*|\([^)]*\)\s*|\d+\s+)*"#

    /// The first sense of an entry, on one line. "serendipity | pron | noun the occurrence of events by chance: a
    /// fortunate stroke" becomes "the occurrence of events by chance".
    nonisolated static func firstSense(_ text: String) -> String? {
        var rest = text
        // Skip the headword and its pronunciation, then the part of speech, when there is one.
        let searchStart = text.firstIndex(of: "|").map { text.index(after: $0) } ?? text.startIndex
        if let range = text.range(of: partsOfSpeech, options: .regularExpression, range: searchStart..<text.endIndex) {
            rest = String(text[range.upperBound...])
        }
        while let range = rest.range(of: leading, options: .regularExpression), !range.isEmpty {
            rest.removeSubrange(range)
        }
        for stop in [":", "\u{2022}", " ORIGIN", " PHRASES", ". "] {
            if let range = rest.range(of: stop) { rest = String(rest[..<range.lowerBound]) }
        }
        rest = rest.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .;:,").union(.whitespacesAndNewlines))
        guard !rest.isEmpty else { return nil }
        return rest.count > 120 ? String(rest.prefix(119)) + "\u{2026}" : rest
    }
}

// MARK: Units

enum UnitConversion {
    struct Request: Equatable {
        let value: Double
        let from: Dimension
        let to: Dimension
    }

    private nonisolated static let aliases: [String: Dimension] = {
        var table: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { for name in names { table[name] = unit } }
        add(UnitLength.meters, "m", "meter", "meters", "metre", "metres")
        add(UnitLength.kilometers, "km", "kilometer", "kilometers", "kilometre", "kilometres")
        add(UnitLength.centimeters, "cm", "centimeter", "centimeters", "centimetre", "centimetres")
        add(UnitLength.millimeters, "mm", "millimeter", "millimeters", "millimetre", "millimetres")
        add(UnitLength.miles, "mi", "mile", "miles")
        add(UnitLength.yards, "yd", "yds", "yard", "yards")
        add(UnitLength.feet, "ft", "foot", "feet")
        add(UnitLength.inches, "in", "inch", "inches", "\"")
        add(UnitMass.kilograms, "kg", "kgs", "kilogram", "kilograms", "kilo", "kilos")
        add(UnitMass.grams, "g", "gram", "grams")
        add(UnitMass.milligrams, "mg", "milligram", "milligrams")
        add(UnitMass.pounds, "lb", "lbs", "pound", "pounds")
        add(UnitMass.ounces, "oz", "ounce", "ounces")
        add(UnitMass.stones, "st", "stone", "stones")
        add(UnitMass.metricTons, "t", "tonne", "tonnes", "ton", "tons")
        add(UnitVolume.liters, "l", "liter", "liters", "litre", "litres")
        add(UnitVolume.milliliters, "ml", "milliliter", "milliliters", "millilitre", "millilitres")
        add(UnitVolume.gallons, "gal", "gallon", "gallons")
        add(UnitVolume.quarts, "qt", "quart", "quarts")
        add(UnitVolume.pints, "pt", "pint", "pints")
        add(UnitVolume.cups, "cup", "cups")
        add(UnitVolume.fluidOunces, "fl oz", "floz", "fluid ounce", "fluid ounces")
        add(UnitVolume.tablespoons, "tbsp", "tablespoon", "tablespoons")
        add(UnitVolume.teaspoons, "tsp", "teaspoon", "teaspoons")
        add(UnitTemperature.celsius, "c", "celsius", "centigrade")
        add(UnitTemperature.fahrenheit, "f", "fahrenheit")
        add(UnitTemperature.kelvin, "k", "kelvin")
        add(UnitSpeed.milesPerHour, "mph")
        add(UnitSpeed.kilometersPerHour, "kph", "kmh", "km/h", "kmph")
        add(UnitSpeed.metersPerSecond, "m/s", "mps")
        add(UnitSpeed.knots, "kn", "kt", "knot", "knots")
        add(UnitArea.squareMeters, "sqm", "m2", "m\u{00B2}", "sq m")
        add(UnitArea.squareKilometers, "sqkm", "km2", "km\u{00B2}", "sq km")
        add(UnitArea.squareFeet, "sqft", "ft2", "ft\u{00B2}", "sq ft")
        add(UnitArea.squareMiles, "sqmi", "mi2", "mi\u{00B2}", "sq mi")
        add(UnitArea.acres, "acre", "acres", "ac")
        add(UnitArea.hectares, "ha", "hectare", "hectares")
        add(UnitDuration.seconds, "s", "sec", "secs", "second", "seconds")
        add(UnitDuration.milliseconds, "ms", "millisecond", "milliseconds")
        add(UnitDuration.minutes, "min", "mins", "minute", "minutes")
        add(UnitDuration.hours, "h", "hr", "hrs", "hour", "hours")
        add(UnitInformationStorage.bytes, "byte", "bytes")
        add(UnitInformationStorage.bits, "bit", "bits")
        add(UnitInformationStorage.kilobytes, "kb", "kilobyte", "kilobytes")
        add(UnitInformationStorage.megabytes, "mb", "megabyte", "megabytes")
        add(UnitInformationStorage.gigabytes, "gb", "gigabyte", "gigabytes")
        add(UnitInformationStorage.terabytes, "tb", "terabyte", "terabytes")
        add(UnitInformationStorage.petabytes, "pb", "petabyte", "petabytes")
        add(UnitInformationStorage.kibibytes, "kib")
        add(UnitInformationStorage.mebibytes, "mib")
        add(UnitInformationStorage.gibibytes, "gib")
        add(UnitInformationStorage.tebibytes, "tib")
        return table
    }()

    private nonisolated static let pattern =
        #"^(-?\d+(?:[.,]\d+)?)\s*([a-z"/\x{00B2} ]+?)\s+(?:in|to|as|into)\s+([a-z"/\x{00B2} ]+)$"#

    /// "5 km in mi", "72f to c", "8 fl oz to ml": a number, a unit, and another unit of the same kind.
    nonisolated static func parse(_ s: String) -> Request? {
        let text = s.lowercased().replacingOccurrences(of: "\u{00B0}", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let match = text.firstMatch(of: pattern), match.count == 3,
            let value = Double(match[0].replacingOccurrences(of: ",", with: ".")),
            let from = aliases[match[1]], let to = aliases[match[2]],
            type(of: from) == type(of: to)
        else { return nil }
        return Request(value: value, from: from, to: to)
    }

    nonisolated static func result(_ request: Request) -> Double {
        Measurement(value: request.value, unit: request.from).converted(to: request.to).value
    }

    /// "3.11 mi": two decimals, or three significant digits for small values.
    nonisolated static func format(_ request: Request, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let value = result(request)
        if abs(value) < 1 && value != 0 {
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 3
        } else {
            formatter.maximumFractionDigits = 2
        }
        let number = formatter.string(from: NSNumber(value: value)) ?? String(value)
        let symbol = request.to.symbol
        return symbol.hasPrefix("\u{00B0}") ? number + symbol : number + " " + symbol
    }
}

private extension String {
    /// The capture groups of the first match of `pattern`, or `nil`.
    nonisolated func firstMatch(of pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: self, range: NSRange(startIndex..., in: self))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: self).map { String(self[$0]) }
        }
    }
}

// MARK: Calculate

/// A small recursive-descent evaluator: `+ - * / ^`, brackets, unary minus, and `×` `÷`. It never throws
/// and never crashes on bad input (`NSExpression` raises Objective-C exceptions).
enum Calculator {
    private static let maxDepth = 40

    /// `nil` unless the text is arithmetic with at least one operator or bracket, and finite.
    nonisolated static func evaluate(_ s: String) -> Double? {
        let text = s.replacingOccurrences(of: "\u{00D7}", with: "*").replacingOccurrences(of: "\u{00F7}", with: "/")
        var parser = Parser(characters: Array(text.filter { !$0.isWhitespace }))
        guard !parser.characters.isEmpty, let value = parser.expression(depth: 0), parser.isAtEnd, parser.usedOperator,
            value.isFinite
        else { return nil }
        return value
    }

    /// Whole numbers without a decimal point; otherwise up to ten significant digits.
    nonisolated static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.10g", value)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        var usedOperator = false

        init(characters: [Character]) { self.characters = characters }

        var isAtEnd: Bool { index >= characters.count }
        private var current: Character? { isAtEnd ? nil : characters[index] }

        mutating func expression(depth: Int) -> Double? {
            guard depth < Calculator.maxDepth, var value = term(depth: depth) else { return nil }
            while let op = current, op == "+" || op == "-" {
                index += 1
                usedOperator = true
                guard let next = term(depth: depth) else { return nil }
                value = op == "+" ? value + next : value - next
            }
            return value
        }

        private mutating func term(depth: Int) -> Double? {
            guard var value = power(depth: depth) else { return nil }
            while let op = current, op == "*" || op == "/" {
                index += 1
                usedOperator = true
                guard let next = power(depth: depth) else { return nil }
                value = op == "*" ? value * next : value / next
            }
            return value
        }

        private mutating func power(depth: Int) -> Double? {
            guard let base = unary(depth: depth) else { return nil }
            if current == "^" {
                index += 1
                usedOperator = true
                guard let exponent = power(depth: depth + 1) else { return nil }  // right to left
                return Foundation.pow(base, exponent)
            }
            return base
        }

        private mutating func unary(depth: Int) -> Double? {
            if let sign = current, sign == "-" || sign == "+" {
                index += 1
                guard depth < Calculator.maxDepth, let value = unary(depth: depth + 1) else { return nil }
                usedOperator = true
                return sign == "-" ? -value : value
            }
            return primary(depth: depth)
        }

        private mutating func primary(depth: Int) -> Double? {
            if current == "(" {
                index += 1
                usedOperator = true
                guard let value = expression(depth: depth + 1), current == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while let character = current, character.isASCII, character.isNumber || character == "." { index += 1 }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]))
        }
    }
}

// MARK: Currency

struct CurrencyRequest: Equatable {
    let amount: Double
    let from: String
    let to: String

    /// The currencies the European Central Bank publishes rates for.
    nonisolated static let supported: Set<String> = [
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY",
        "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    private nonisolated static let symbols: [String: String] = ["$": "USD", "\u{20AC}": "EUR", "\u{00A3}": "GBP", "\u{00A5}": "JPY"]

    /// "100 usd in eur", "$20 to gbp", "\u{20AC}50 to $": an amount, a currency, and another.
    nonisolated static func parse(_ s: String) -> CurrencyRequest? {
        let text = s.trimmingCharacters(in: .whitespaces)
        let money = #"([€$£¥]|[A-Za-z]{3})"#
        let separator = #"\s+(?:in|to|as|into)\s+"#
        let amount = #"(\d+(?:[.,]\d+)*)"#
        var groups: (amount: String, from: String, to: String)?
        if let match = text.firstMatch(of: "^([€$£¥])\\s*" + amount + separator + money + "$"), match.count == 3 {
            groups = (match[1], match[0], match[2])
        } else if let match = text.firstMatch(of: "^" + amount + "\\s*" + money + separator + money + "$"), match.count == 3 {
            groups = (match[0], match[1], match[2])
        }
        guard let groups, let amount = number(groups.amount),
            let from = code(groups.from), let to = code(groups.to), from != to
        else { return nil }
        return CurrencyRequest(amount: amount, from: from, to: to)
    }

    private nonisolated static func code(_ text: String) -> String? {
        let code = symbols[text] ?? text.uppercased()
        return supported.contains(code) ? code : nil
    }

    /// "1,000.50" and "1000.5" alike; a lone comma is a decimal point.
    private nonisolated static func number(_ text: String) -> Double? {
        let hasDot = text.contains(".")
        let commas = text.filter { $0 == "," }.count
        if hasDot || commas > 1 { return Double(text.replacingOccurrences(of: ",", with: "")) }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    nonisolated static func format(_ amount: Double, code: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount) + " " + code
    }
}
