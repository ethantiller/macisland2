import Foundation
import Observation

/// Exchange rates from Frankfurter (free, no key, European Central Bank data). Fetched only when a
/// currency query is typed, and kept for 12 hours per base currency.
@MainActor
@Observable
final class ExchangeRates {
    typealias Fetch = @Sendable (String) async throws -> (rates: [String: Double], date: Date)

    static let maxAge: TimeInterval = 12 * 60 * 60

    private struct Table {
        let rates: [String: Double]
        /// The day the rates are for, shown to the person.
        let date: Date
        let fetchedAt: Date
    }

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let now: () -> Date
    private var tables: [String: Table] = [:]

    init(fetch: @escaping Fetch = ExchangeRates.fetchFromNetwork, now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.now = now
    }

    /// One `from` is worth `value` of `to`, as of `date`. Reads the cache only.
    func rate(from: String, to: String) -> (value: Double, date: Date)? {
        if from == to { return (1, now()) }
        guard let table = tables[from], let value = table.rates[to] else { return nil }
        return (value, table.date)
    }

    func hasRates(for base: String) -> Bool { tables[base] != nil }

    /// Fetches the rates for `base` unless the cache already has them from the last 12 hours.
    func load(base: String) async {
        if let table = tables[base], now().timeIntervalSince(table.fetchedAt) < Self.maxAge { return }
        guard let result = try? await fetch(base) else { return }
        tables[base] = Table(rates: result.rates, date: result.date, fetchedAt: now())
    }

    // MARK: Network

    nonisolated static func url(base: String) -> URL? {
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")
        components?.queryItems = [URLQueryItem(name: "base", value: base)]
        return components?.url
    }

    /// `{"base":"USD","date":"2026-09-29","rates":{"EUR":0.88,...}}`
    nonisolated static func parse(_ data: Data) -> (rates: [String: Double], date: Date)? {
        struct Response: Decodable {
            let date: String
            let rates: [String: Double]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), !response.rates.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (response.rates, formatter.date(from: response.date) ?? Date())
    }

    @Sendable
    nonisolated static func fetchFromNetwork(base: String) async throws -> (rates: [String: Double], date: Date) {
        guard let url = url(base: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let parsed = parse(data) else { throw URLError(.cannotParseResponse) }
        return parsed
    }
}
