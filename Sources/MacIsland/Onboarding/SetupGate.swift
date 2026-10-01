import Observation

/// Whether setup is complete: the guide has been finished and every permission is allowed. Until it is, MacIsland shows only the guide:
/// the island is out of sight, the shortcuts go to the guide, and the menu bar offers Continue Setup and Quit. `AppDelegate` opens and
/// closes it (`updateSetupGate`), and the menu bar reads it.
@MainActor
@Observable
final class SetupGate {
    private(set) var isOpen = false

    /// What opens it.
    nonisolated static func isComplete(needsGuide: Bool, allAllowed: Bool) -> Bool { !needsGuide && allAllowed }

    func open() { isOpen = true }
    func close() { isOpen = false }
}
