import Observation
import SwiftUI

/// Things the island is busy doing for you: zipping, converting. Shown beside the notch in the
/// "in progress" blue while any are running.
@MainActor
@Observable
final class WorkTracker {
    struct Job: Identifiable, Equatable {
        let id = UUID()
        var title: String
    }

    private(set) var jobs: [Job] = []

    /// The job to name beside the notch.
    var current: Job? { jobs.first }

    @discardableResult
    func begin(_ title: String) -> UUID {
        let job = Job(title: title)
        withAnimation(Theme.Motion.open) { jobs.append(job) }
        return job.id
    }

    func end(_ id: UUID) {
        withAnimation(Theme.Motion.close) { jobs.removeAll { $0.id == id } }
    }
}
