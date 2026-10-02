import Foundation

/// How far back the Stats mode counts.
enum StatsRange: String, CaseIterable, Identifiable {
    case all = "All Time"
    case month = "30 Days"
    case week = "7 Days"

    var id: Self { self }

    /// The days counted, today included; nil for all of them.
    var days: Int? {
        switch self {
        case .all: nil
        case .month: 30
        case .week: 7
        }
    }
}

/// A year of days as 53 columns of 7 (a week to a column), four steps of white by quartile of the days that had use, and how many days
/// in a row the agents were used.
struct YearMap: Equatable {
    struct Cell: Equatable, Identifiable {
        var id: Int
        /// The day, or nil for a day that hasn't come yet.
        var date: Date?
        var day: Int
        /// 0 for no use, then 1 to 4 by quartile of the days that had some.
        var level: Int
        var tokens: Int
    }

    struct MonthLabel: Equatable {
        var column: Int
        var title: String
    }

    static let rows = 7

    /// Columns of weeks, oldest first; each column from the first weekday down.
    var weeks: [[Cell]] = []
    var monthLabels: [MonthLabel] = []
    var streak = 0
    var activeDays = 0

    /// `agent` filters to one tool; nil is both.
    static func make(
        buckets: [UsageBucket], now: Date, agent: AgentKind? = nil, weeks columns: Int = 53, calendar: Calendar = .current
    ) -> YearMap {
        var perDay: [Int: Int] = [:]
        for bucket in buckets where agent == nil || bucket.agent == agent { perDay[bucket.day, default: 0] += bucket.tokens.total }

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

        var map = YearMap()
        for column in 0..<columns {
            var week: [Cell] = []
            for row in 0..<rows {
                let offset = column * rows + row
                let date = calendar.date(byAdding: .day, value: offset, to: first)
                guard let date, date <= today else {
                    week.append(Cell(id: offset, date: nil, day: 0, level: 0, tokens: 0))
                    continue
                }
                let day = UsageDay.key(date, calendar: calendar)
                let tokens = perDay[day] ?? 0
                let level = tokens <= 0 ? 0 : tokens <= q1 ? 1 : tokens <= q2 ? 2 : tokens <= q3 ? 3 : 4
                week.append(Cell(id: offset, date: date, day: day, level: level, tokens: tokens))
            }
            map.weeks.append(week)
        }
        let cells = map.weeks.flatMap { $0 }
        map.activeDays = cells.filter { $0.level > 0 }.count
        map.streak = Self.streak(of: cells.compactMap { $0.date == nil ? nil : $0.tokens > 0 })
        map.monthLabels = Self.monthLabels(weeks: map.weeks, calendar: calendar)
        return map
    }

    /// A month's name over the first column that starts in it, with room for the name before the next.
    private static func monthLabels(weeks: [[Cell]], calendar: Calendar) -> [MonthLabel] {
        var labels: [MonthLabel] = []
        var previousMonth: Int?
        for (column, week) in weeks.enumerated() {
            guard let date = week.first(where: { $0.date != nil })?.date else { continue }
            let month = calendar.component(.month, from: date)
            defer { previousMonth = month }
            guard month != previousMonth else { continue }
            if let last = labels.last, column - last.column < 3 { continue }
            labels.append(MonthLabel(column: column, title: calendar.shortMonthSymbols[month - 1]))
        }
        return labels
    }

    /// Days in a row up to today, or up to yesterday if today hasn't had any yet. `days` runs oldest first.
    static func streak(of days: [Bool]) -> Int {
        var index = days.count - 1
        if index >= 0, !days[index] { index -= 1 }
        var count = 0
        while index >= 0, days[index] {
            count += 1
            index -= 1
        }
        return count
    }

    /// The longest run of days in a row.
    static func longestStreak(of days: [Bool]) -> Int {
        var best = 0
        var run = 0
        for day in days {
            run = day ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }
}

/// What the Stats mode says over a range: tokens, what they would cost, sessions, and the habits behind them. Pure.
struct AgentStats: Equatable {
    var tokens = 0
    var value = 0.0
    /// A model without a price was used, so the value is at least this.
    var isLowerBound = false
    var favoriteModel: String?
    var sessions = 0
    var longestSession: TimeInterval = 0
    var activeDays = 0
    var rangeDays = 0
    var currentStreak = 0
    var longestStreak = 0
    var mostActiveDay: (day: Int, tokens: Int)?
    var peakHour: Int?
    var cacheSaving = 0.0
    var funFact: String?

    static func == (lhs: AgentStats, rhs: AgentStats) -> Bool {
        lhs.tokens == rhs.tokens && lhs.value == rhs.value && lhs.isLowerBound == rhs.isLowerBound
            && lhs.favoriteModel == rhs.favoriteModel && lhs.sessions == rhs.sessions
            && lhs.longestSession == rhs.longestSession && lhs.activeDays == rhs.activeDays && lhs.rangeDays == rhs.rangeDays
            && lhs.currentStreak == rhs.currentStreak && lhs.longestStreak == rhs.longestStreak
            && lhs.mostActiveDay?.day == rhs.mostActiveDay?.day && lhs.mostActiveDay?.tokens == rhs.mostActiveDay?.tokens
            && lhs.peakHour == rhs.peakHour && lhs.cacheSaving == rhs.cacheSaving && lhs.funFact == rhs.funFact
    }

    /// About how many tokens *War and Peace* is, for the fun fact.
    static let warAndPeaceTokens = 780_000
    static let nightOfSleep: TimeInterval = 8 * 3_600

    var hasUse: Bool { tokens > 0 }

    static func make(
        snapshot: AgentUsageSnapshot, agent: AgentKind?, range: StatsRange, now: Date, pricing: AgentPricing,
        calendar: Calendar = .current
    ) -> AgentStats {
        let today = UsageDay.key(now, calendar: calendar)
        let firstDay: Int? = range.days.flatMap { days in
            calendar.date(byAdding: .day, value: -(days - 1), to: now).map { UsageDay.key($0, calendar: calendar) }
        }
        func inRange(_ day: Int) -> Bool { day <= today && (firstDay.map { day >= $0 } ?? true) }
        let buckets = snapshot.buckets.filter { (agent == nil || $0.agent == agent) && inRange($0.day) }

        var stats = AgentStats()
        var perDay: [Int: Int] = [:]
        var perModel: [String: Int] = [:]
        for bucket in buckets {
            stats.tokens += bucket.tokens.total
            perDay[bucket.day, default: 0] += bucket.tokens.total
            perModel[AgentLogParser.prettyModel(bucket.model), default: 0] += bucket.tokens.total
            if let cost = pricing.cost(of: bucket.tokens, model: bucket.model) {
                stats.value += cost
                stats.cacheSaving += pricing.cacheSaving(of: bucket.tokens, model: bucket.model) ?? 0
            } else if bucket.tokens.total > 0 {
                stats.isLowerBound = true
            }
        }
        stats.favoriteModel = perModel.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key

        // Sessions whose last request falls in the range.
        let sessions = snapshot.sessions.filter { session in
            guard agent == nil || session.agent == agent else { return false }
            return inRange(UsageDay.key(Date(timeIntervalSince1970: session.last), calendar: calendar))
        }
        stats.sessions = sessions.count
        stats.longestSession = sessions.map(\.duration).max() ?? 0

        // The days counted: the range, or since the first day with use.
        var days: [Date] = []
        let earliest = perDay.keys.min().flatMap { UsageDay.date($0, calendar: calendar) }
        let startDate: Date? = range.days.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: calendar.startOfDay(for: now)) } ?? earliest
        if let startDate {
            var cursor = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: now)
            while cursor <= end {
                days.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        let activeFlags = days.map { (perDay[UsageDay.key($0, calendar: calendar)] ?? 0) > 0 }
        stats.rangeDays = days.count
        stats.activeDays = activeFlags.filter { $0 }.count
        stats.currentStreak = YearMap.streak(of: activeFlags)
        stats.longestStreak = YearMap.longestStreak(of: activeFlags)
        stats.mostActiveDay = perDay.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }

        var perHour = Array(repeating: 0, count: 24)
        for (key, counts) in snapshot.hours {
            let parts = key.split(separator: "|")
            guard parts.count == 2, let day = Int(parts[0]), inRange(day) else { continue }
            if let agent, String(parts[1]) != agent.rawValue { continue }
            for (hour, count) in counts.enumerated() where hour < 24 { perHour[hour] += count }
        }
        if let best = perHour.max(), best > 0 { stats.peakHour = perHour.firstIndex(of: best) }

        stats.funFact = funFact(longestSession: stats.longestSession, tokens: stats.tokens)
        return stats
    }

    /// One line by a fixed rule: the longest session against nights of sleep if it is at least two; otherwise the tokens against
    /// *War and Peace* if they are at least two of them; otherwise nothing.
    static func funFact(longestSession: TimeInterval, tokens: Int) -> String? {
        if longestSession >= 2 * nightOfSleep {
            let nights = Int((longestSession / nightOfSleep).rounded())
            return "Longest session \u{2248} \(nights) nights of sleep"
        }
        let books = tokens / warAndPeaceTokens
        if books >= 2 { return "That is \u{2248} \(books) \u{00D7} War and Peace" }
        return nil
    }
}
