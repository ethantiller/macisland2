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

/// The last 91 days as 13 columns of 7 days, and how many days in a row the agents were used.
struct ActivityMap: Equatable {
    struct Cell: Equatable, Identifiable {
        var id: Int
        /// The day, or nil for a day that hasn't come yet.
        var date: Date?
        /// 0 for no use, then 1 to 4 by quartile of the days that had some.
        var level: Int
        var tokens: Int
    }

    static let columns = 13
    static let rows = 7

    /// Columns of weeks, oldest first; each column from the first weekday down.
    var weeks: [[Cell]] = []
    var streak = 0
    var activeDays = 0

    static func make(buckets: [UsageBucket], now: Date, calendar: Calendar = .current) -> ActivityMap {
        var perDay: [Int: Int] = [:]
        for bucket in buckets { perDay[bucket.day, default: 0] += bucket.tokens.total }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -7 * (columns - 1), to: weekStart) ?? weekStart
        let today = calendar.startOfDay(for: now)

        let active = perDay.values.filter { $0 > 0 }.sorted()
        func threshold(_ quarter: Int) -> Int {
            guard !active.isEmpty else { return 0 }
            let index = Int((Double(active.count) * Double(quarter) / 4).rounded(.up)) - 1
            return active[max(0, min(index, active.count - 1))]
        }
        let (q1, q2, q3) = (threshold(1), threshold(2), threshold(3))

        var map = ActivityMap()
        for column in 0..<columns {
            var week: [Cell] = []
            for row in 0..<rows {
                let offset = column * rows + row
                let date = calendar.date(byAdding: .day, value: offset, to: first)
                guard let date, date <= today else {
                    week.append(Cell(id: offset, date: nil, level: 0, tokens: 0))
                    continue
                }
                let tokens = perDay[UsageDay.key(date, calendar: calendar)] ?? 0
                let level = tokens <= 0 ? 0 : tokens <= q1 ? 1 : tokens <= q2 ? 2 : tokens <= q3 ? 3 : 4
                week.append(Cell(id: offset, date: date, level: level, tokens: tokens))
            }
            map.weeks.append(week)
        }
        let cells = map.weeks.flatMap { $0 }
        map.activeDays = cells.filter { $0.level > 0 }.count
        // The streak counts back from today, or from yesterday if today hasn't had any yet.
        var index = cells.lastIndex { $0.date != nil } ?? -1
        if index >= 0, cells[index].level == 0 { index -= 1 }
        while index >= 0, cells[index].level > 0 {
            map.streak += 1
            index -= 1
        }
        return map
    }
}
