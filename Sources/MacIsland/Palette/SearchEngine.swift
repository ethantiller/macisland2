import Foundation

/// A web search the command palette can run: nine built in, and the person's own.
struct SearchEngine: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    /// Typed before a query to pick this engine: `yt swift concurrency`.
    var keyword: String
    /// The address, with `%s` where the search goes.
    var template: String

    static let builtIn: [SearchEngine] = [
        SearchEngine(id: "google", name: "Google", keyword: "g", template: "https://www.google.com/search?q=%s"),
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo", keyword: "ddg", template: "https://duckduckgo.com/?q=%s"),
        SearchEngine(id: "bing", name: "Bing", keyword: "b", template: "https://www.bing.com/search?q=%s"),
        SearchEngine(id: "youtube", name: "YouTube", keyword: "yt", template: "https://www.youtube.com/results?search_query=%s"),
        SearchEngine(id: "wikipedia", name: "Wikipedia", keyword: "w", template: "https://en.wikipedia.org/w/index.php?search=%s"),
        SearchEngine(id: "github", name: "GitHub", keyword: "gh", template: "https://github.com/search?q=%s"),
        SearchEngine(id: "maps", name: "Apple Maps", keyword: "m", template: "https://maps.apple.com/?q=%s"),
        SearchEngine(id: "stackoverflow", name: "Stack Overflow", keyword: "so", template: "https://stackoverflow.com/search?q=%s"),
        SearchEngine(id: "amazon", name: "Amazon", keyword: "a", template: "https://www.amazon.com/s?k=%s"),
    ]

    static let defaultID = "google"

    /// The address to open for a query, or `nil` if the template isn't a usable web address.
    func url(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?/:;@$,")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    /// A template needs `%s` and must be an http or https address.
    static func isValid(template: String) -> Bool {
        guard template.contains("%s"),
              let url = URL(string: template.replacingOccurrences(of: "%s", with: "test")),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return false }
        return true
    }

    /// `yt swift` picks YouTube and the query `swift`. Case doesn't matter; the query can't be empty.
    static func match(_ input: String, in engines: [SearchEngine]) -> (engine: SearchEngine, query: String)? {
        let parts = input.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let keyword = parts[0].lowercased()
        let query = parts[1].trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let engine = engines.first(where: { $0.keyword.lowercased() == keyword }) else { return nil }
        return (engine, query)
    }
}
