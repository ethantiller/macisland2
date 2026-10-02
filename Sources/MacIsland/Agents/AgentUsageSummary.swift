import Foundation

/// How far back the Usage mode looks.
enum UsageRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"

    var id: Self { self }

    var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }
}

/// One model or project in a ranking.
struct RankedUsage: Identifiable, Equatable {
    var name: String
    var tokens: Int
    /// Dollars at API prices, nil if the model has no price.
    var value: Double?

    var id: String { name }
}

/// What the agents used over a range, and what it would cost at API prices.
struct AgentUsageSummary: Equatable {
    var value = 0.0
    /// A model without a price was used, so the value is at least this.
    var isLowerBound = false
    var tokens = 0
    var requests = 0
    var cacheSaving = 0.0
    var models: [RankedUsage] = []
    var projects: [RankedUsage] = []

    static func make(
        buckets: [UsageBucket], range: UsageRange, now: Date, pricing: AgentPricing, calendar: Calendar = .current
    ) -> AgentUsageSummary {
        let today = UsageDay.key(now, calendar: calendar)
        let first = calendar.date(byAdding: .day, value: -(range.days - 1), to: now).map { UsageDay.key($0, calendar: calendar) } ?? today
        var summary = AgentUsageSummary()
        var models: [String: RankedUsage] = [:]
        var projects: [String: RankedUsage] = [:]
        for bucket in buckets where bucket.day >= first && bucket.day <= today {
            let cost = pricing.cost(of: bucket.tokens, model: bucket.model)
            summary.tokens += bucket.tokens.total
            summary.requests += bucket.requests
            if let cost {
                summary.value += cost
                summary.cacheSaving += pricing.cacheSaving(of: bucket.tokens, model: bucket.model) ?? 0
            } else if bucket.tokens.total > 0 {
                summary.isLowerBound = true
            }
            func add(_ name: String, to table: inout [String: RankedUsage]) {
                var entry = table[name] ?? RankedUsage(name: name, tokens: 0, value: nil)
                entry.tokens += bucket.tokens.total
                if let cost { entry.value = (entry.value ?? 0) + cost }
                table[name] = entry
            }
            add(AgentPricing.family(of: bucket.model), to: &models)
            add(bucket.project, to: &projects)
        }
        func ranked(_ table: [String: RankedUsage]) -> [RankedUsage] {
            table.values.sorted {
                ($0.value ?? 0, $0.tokens, $1.name) > ($1.value ?? 0, $1.tokens, $0.name)
            }
        }
        summary.models = ranked(models)
        summary.projects = ranked(projects)
        return summary
    }
}
