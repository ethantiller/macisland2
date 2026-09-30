import Foundation

/// A Home arrangement the person saved under a name, to find again in the Presets menu. It is the widgets, their sizes, and their
/// options; what isn't on Home isn't part of it. The built-in presets (`HomeLayout.presets`) can't be removed or replaced.
struct SavedHomePreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var layout: HomeLayout

    /// What saving a name did.
    enum SaveResult: Equatable {
        case saved(SavedHomePreset)
        /// A saved layout already had this name, so it now holds the new arrangement.
        case replaced(SavedHomePreset)
        case empty
        /// The name is a built-in preset's.
        case reserved
    }

    /// The name as it will be kept: without the space around it.
    static func cleaned(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether a built-in preset already has this name, ignoring case.
    static func isBuiltIn(_ name: String) -> Bool {
        HomeLayout.presets.contains { $0.name.caseInsensitiveCompare(cleaned(name)) == .orderedSame }
    }

    /// "My Layout", or "My Layout 2" and on when that is taken.
    static func suggestedName(among saved: [SavedHomePreset]) -> String {
        let taken = Set(saved.map { $0.name.lowercased() })
        if !taken.contains("my layout") { return "My Layout" }
        var number = 2
        while taken.contains("my layout \(number)") { number += 1 }
        return "My Layout \(number)"
    }
}

extension HomeLayout {
    /// Whether the same widgets are on Home at the same sizes, in the same order: what makes a preset the current one.
    func hasSameArrangement(as other: HomeLayout) -> Bool {
        widgets.count == other.widgets.count
            && zip(widgets, other.widgets).allSatisfy { $0.widget == $1.widget && $0.size == $1.size }
    }
}
