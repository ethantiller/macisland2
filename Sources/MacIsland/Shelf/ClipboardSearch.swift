import Foundation

/// Finding something in the clipboard history by typing. Pure, so it is tested. Every word of the query must appear in a copy, in any
/// order, ignoring case and accents. An image has no text, so it matches only an empty query.
enum ClipboardSearch {
    /// The words of a query.
    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Whether `text` has every word of the query.
    static func matches(_ text: String, query: String) -> Bool {
        words(query).allSatisfy { text.range(of: $0, options: options) != nil }
    }

    /// Where the query's words are in `text`, in order, with the overlapping ones joined.
    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for word in words(query) {
            var start = text.startIndex
            while start < text.endIndex,
                let range = text.range(of: word, options: options, range: start..<text.endIndex)
            {
                found.append(range)
                start = range.upperBound
            }
        }
        var joined: [Range<String.Index>] = []
        for range in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = joined.last, range.lowerBound <= last.upperBound {
                joined[joined.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                joined.append(range)
            }
        }
        return joined
    }
}

extension ClipboardEntry {
    func matches(_ query: String) -> Bool {
        if ClipboardSearch.words(query).isEmpty { return true }
        guard case .text(let text) = content else { return false }
        return ClipboardSearch.matches(text, query: query)
    }
}

extension ClipboardHistory {
    /// The copies that match, in history order (newest first). An empty query is everything.
    func matches(_ query: String) -> [ClipboardEntry] {
        entries.filter { $0.matches(query) }
    }
}

extension ClipboardSearch {
    /// `text` cut into runs, each marked as a match of the query or not, for drawing the matched words apart from the rest.
    static func segments(of query: String, in text: String) -> [(text: String, isMatch: Bool)] {
        var result: [(text: String, isMatch: Bool)] = []
        var cursor = text.startIndex
        for range in ranges(of: query, in: text) {
            if cursor < range.lowerBound { result.append((String(text[cursor..<range.lowerBound]), false)) }
            result.append((String(text[range]), true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { result.append((String(text[cursor...]), false)) }
        return result
    }
}
