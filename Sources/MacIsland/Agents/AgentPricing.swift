import Foundation

/// Dollars per million tokens, for one model.
struct AgentPrice: Codable, Equatable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
    /// The one-hour cache write, when it has its own price; otherwise `cacheWrite`.
    var cacheWrite1h: Double?
}

/// The tokens of one or more requests, in the four kinds that are priced.
struct AgentTokens: Codable, Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    /// Written to the five-minute cache.
    var cacheWrite = 0
    /// Written to the one-hour cache.
    var cacheWrite1h = 0

    var total: Int { input + output + cacheRead + cacheWrite + cacheWrite1h }

    static func + (lhs: AgentTokens, rhs: AgentTokens) -> AgentTokens {
        AgentTokens(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output, cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite, cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h)
    }

    static func += (lhs: inout AgentTokens, rhs: AgentTokens) { lhs = lhs + rhs }
}

/// What the agents' tokens would cost at API prices. The table is a bundled file (`Resources/agent-prices.json`), read at build time
/// from the published pricing pages: nothing is downloaded. A model with no entry adds no value.
struct AgentPricing: Equatable {
    var updated: String
    var models: [String: AgentPrice]

    private struct File: Decodable {
        var updated: String
        var models: [String: AgentPrice]
    }

    init(updated: String = "", models: [String: AgentPrice] = [:]) {
        self.updated = updated
        self.models = models
    }

    init?(data: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        self.init(updated: file.updated, models: file.models)
    }

    /// The bundled table, or an empty one (every model unpriced) if the file is missing.
    static let bundled: AgentPricing = {
        let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("MacIsland_MacIsland.bundle")
        let bundle = bundleURL.flatMap { Bundle(path: $0.path) } ?? Bundle.module
        guard let url = bundle.url(forResource: "agent-prices", withExtension: "json"),
            let data = try? Data(contentsOf: url), let pricing = AgentPricing(data: data)
        else { return AgentPricing() }
        return pricing
    }()

    /// "claude-opus-4-5-20251101" is "opus-4-5"; a name without "claude-" is only lowercased.
    static func family(of model: String) -> String {
        var name = model.lowercased()
        if name.hasPrefix("claude-") { name.removeFirst("claude-".count) }
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(range) }
        return name
    }

    /// The price of a model: the entry whose name is the longest prefix of the model's family name, at a dash.
    func price(for model: String) -> AgentPrice? {
        let name = Self.family(of: model)
        let match = models.keys.filter { name == $0 || name.hasPrefix($0 + "-") }.max { $0.count < $1.count }
        return match.flatMap { models[$0] }
    }

    /// Dollars for these tokens, or nil if the model has no price.
    func cost(of tokens: AgentTokens, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        let million = 1_000_000.0
        return (Double(tokens.input) * price.input + Double(tokens.output) * price.output
            + Double(tokens.cacheRead) * price.cacheRead + Double(tokens.cacheWrite) * price.cacheWrite
            + Double(tokens.cacheWrite1h) * (price.cacheWrite1h ?? price.cacheWrite)) / million
    }

    /// What reading the cache saved: cache-read tokens times what they would have cost as input, less what they cost.
    func cacheSaving(of tokens: AgentTokens, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        return Double(tokens.cacheRead) * max(price.input - price.cacheRead, 0) / 1_000_000
    }
}
