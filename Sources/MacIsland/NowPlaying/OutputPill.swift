import SwiftUI

/// How wide an output satellite is: a circle, or while hovered a pill only as wide as its name (up to the cap).
enum OutputPill {
    /// Side padding, the glyph, and the space between the glyph and the name.
    private static let chrome: CGFloat = 8 * 2 + 24 + 7

    static func width(textWidth: CGFloat) -> CGFloat {
        min(Theme.Metrics.outputPillMaxWidth, max(Theme.Metrics.outputSatelliteSize, chrome + textWidth))
    }

    /// Where the column of `count` satellites ends, from the top of its first.
    static func columnHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let size = Theme.Metrics.outputSatelliteSize
        return CGFloat(count) * size + CGFloat(count - 1) * Theme.Metrics.outputSatelliteSpacing
    }

    /// The centre of the `index`th satellite from the top of the column.
    static func centerY(index: Int) -> CGFloat {
        let size = Theme.Metrics.outputSatelliteSize
        return CGFloat(index) * (size + Theme.Metrics.outputSatelliteSpacing) + size / 2
    }
}
