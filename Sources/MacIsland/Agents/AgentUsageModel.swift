import Foundation
import Observation

/// What the Usage and Activity modes, the Agents widget, and the limit notice show. It holds the last snapshot of the store and asks
/// for a fresh one: when a view appears, and a few seconds after an agent's log changes. Nothing polls. The work is the store's, at
/// utility priority.
@MainActor
@Observable
final class AgentUsageModel {
    private(set) var snapshot: AgentUsageSnapshot?
    private(set) var isLoading = false

    @ObservationIgnored let pricing: AgentPricing
    @ObservationIgnored private let store: AgentUsageStore
    /// Set while Agents is on. A model that is off never touches the disk.
    private(set) var isEnabled = false
    /// What a refresh needs from Settings, asked each time so a change applies at once.
    @ObservationIgnored var request: () -> AgentUsageRequest = { AgentUsageRequest() }
    /// A limit crossed the threshold: the app flashes the notice.
    @ObservationIgnored var onLimit: ((AgentLimit) -> Void)?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var wantsAnother = false
    /// How long after a log changes the usage is read again.
    @ObservationIgnored var settleDelay: Duration = .seconds(3)

    init(store: AgentUsageStore = AgentUsageStore(), pricing: AgentPricing = .bundled) {
        self.store = store
        self.pricing = pricing
    }

    /// The Settings preview and tests show a snapshot without reading anything.
    func show(_ snapshot: AgentUsageSnapshot) {
        self.snapshot = snapshot
    }

    func start() {
        isEnabled = true
        Task { await refresh() }
    }

    /// Switched off: what was read is forgotten, and so is the cache file.
    func stop() {
        let wasOn = isEnabled
        isEnabled = false
        debounce?.cancel()
        debounce = nil
        wantsAnother = false
        snapshot = nil
        // Only a model that was reading has a cache to delete.
        guard wasOn else { return }
        let store = store
        Task.detached(priority: .utility) { await store.clear() }
    }

    func refresh() async {
        guard isEnabled else { return }
        if isLoading {
            wantsAnother = true
            return
        }
        isLoading = true
        let asked = request()
        let store = store
        let result = await Task.detached(priority: .utility) { await store.refresh(asked) }.value
        isLoading = false
        guard isEnabled else { return }
        snapshot = result
        for limit in result.newlyOver { onLimit?(limit) }
        if wantsAnother {
            wantsAnother = false
            await refresh()
        }
    }

    /// An agent's log changed: look again once it settles.
    func activity() {
        guard isEnabled else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            guard let delay = self?.settleDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}

extension AgentUsageSnapshot {
    /// The limit of an agent's window, if there is one.
    func limit(_ agent: AgentKind, _ kind: AgentLimitKind) -> AgentLimit? {
        limits.first { $0.agent == agent && $0.kind == kind }
    }

    /// The window with the most used, for the widget's ring.
    var busiestLimit: AgentLimit? {
        limits.filter { $0.percent != nil }.max { ($0.percent ?? 0) < ($1.percent ?? 0) }
    }
}
