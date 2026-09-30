import Foundation

/// Precipitation for one quarter hour, in millimeters.
struct RainSample: Equatable {
    let time: Date
    let millimeters: Double
}

/// When to say "Rain Soon": it is dry now and at least 0.2 mm is forecast to start within 30 minutes.
enum RainRule {
    static let threshold = 0.2
    static let lookahead: TimeInterval = 30 * 60
    static let step: TimeInterval = 15 * 60

    /// Rain is falling in the quarter hour that contains `now`.
    nonisolated static func isWet(samples: [RainSample], now: Date) -> Bool {
        samples.contains { $0.time <= now && now < $0.time.addingTimeInterval(step) && $0.millimeters >= threshold }
    }

    /// When the coming rain starts, or `nil` if it is raining already or none is due within half an hour.
    nonisolated static func start(samples: [RainSample], now: Date) -> Date? {
        guard !isWet(samples: samples, now: now) else { return nil }
        return samples
            .filter { $0.time > now && $0.time <= now.addingTimeInterval(lookahead) && $0.millimeters >= threshold }
            .map(\.time)
            .min()
    }
}

/// Says it once per rain spell: after a warning, the next one waits until it has been dry for an hour.
struct RainSpell {
    static let dryPeriod: TimeInterval = 60 * 60

    private(set) var announcedAt: Date?
    private var lastWet: Date?

    mutating func shouldAnnounce(start: Date?, wetNow: Bool, now: Date) -> Bool {
        if wetNow { lastWet = now }
        if let announcedAt, now.timeIntervalSince(max(announcedAt, lastWet ?? .distantPast)) >= Self.dryPeriod {
            self.announcedAt = nil
        }
        guard start != nil, announcedAt == nil else { return false }
        announcedAt = now
        return true
    }
}
