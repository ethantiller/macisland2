import Foundation

/// Ranking for the command palette: how well a typed query matches a name.
enum PaletteSearch {
    /// Higher is better; `nil` is no match. An exact name beats a prefix, which beats the start of a word, then
    /// somewhere inside, then the letters in order ("ntb" finds "Notebook").
    nonisolated static func score(query: String, in text: String) -> Double? {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        let text = text.lowercased()
        guard !query.isEmpty, !text.isEmpty else { return nil }

        if text == query { return 1000 }
        if text.hasPrefix(query) { return 800 - Double(text.count - query.count) * 0.5 }
        if let range = text.range(of: query) {
            let atWordStart = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
                && !text[text.index(before: range.lowerBound)].isNumber
            return (atWordStart ? 600 : 400) - Double(text.count - query.count) * 0.5
        }
        return subsequenceScore(query: query, text: text)
    }

    /// The letters of `query` in order within `text`; tighter runs score higher.
    private nonisolated static func subsequenceScore(query: String, text: String) -> Double? {
        var index = text.startIndex
        var gaps = 0
        var last: String.Index?
        for character in query {
            guard let found = text[index...].firstIndex(of: character) else { return nil }
            if let last, text.index(after: last) != found { gaps += 1 }
            last = found
            index = text.index(after: found)
        }
        return max(200 - Double(gaps) * 20, 20)
    }

    /// The best score over several names (a title and its keywords).
    nonisolated static func bestScore(query: String, in names: [String]) -> Double? {
        names.compactMap { score(query: query, in: $0) }.max()
    }
}

/// "25m", "1h30m", "90 min", "timer 45": minutes for a timer, rounded up, at least one.
enum PaletteTimer {
    nonisolated static func minutes(from input: String) -> Int? {
        var text = input.lowercased().trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("timer ") { text.removeFirst("timer ".count) }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let pattern = #"^(?:(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours))?\s*(?:(\d+)\s*(?:m|min|mins|minute|minutes))?\s*(?:(\d+)\s*(?:s|sec|secs|second|seconds))?$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.range(at: 1).location != NSNotFound || match.range(at: 2).location != NSNotFound || match.range(at: 3).location != NSNotFound {
            func value(_ group: Int) -> Double {
                Range(match.range(at: group), in: text).flatMap { Double(text[$0]) } ?? 0
            }
            let seconds = value(1) * 3600 + value(2) * 60 + value(3)
            return seconds > 0 ? max(Int((seconds / 60).rounded(.up)), 1) : nil
        }
        // A bare number after "timer" means minutes.
        return input.lowercased().hasPrefix("timer ") ? Int(text).flatMap { $0 > 0 ? $0 : nil } : nil
    }
}

/// "tr hello" or "translate es hello": what to translate, and into which language.
struct TranslationRequest: Equatable {
    let text: String
    /// A language identifier, like "es" or "fr".
    let target: String

    nonisolated static func parse(_ input: String, systemLanguage: String = Locale.current.language.languageCode?.identifier ?? "en") -> TranslationRequest? {
        let parts = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, ["tr", "translate"].contains(parts[0].lowercased()) else { return nil }
        let rest = Array(parts.dropFirst())
        if rest.count >= 2, let code = languageCode(rest[0]) {
            return TranslationRequest(text: rest.dropFirst().joined(separator: " "), target: code)
        }
        return TranslationRequest(text: rest.joined(separator: " "), target: systemLanguage)
    }

    /// A two-letter ISO 639 code the system knows.
    private nonisolated static func languageCode(_ token: String) -> String? {
        let code = token.lowercased()
        guard code.count == 2, Locale.LanguageCode.isoLanguageCodes.contains(where: { $0.identifier == code }) else { return nil }
        return code
    }

    /// The language's own name in the current language, for the row's title.
    var targetName: String {
        Locale.current.localizedString(forLanguageCode: target)?.capitalized ?? target
    }
}
