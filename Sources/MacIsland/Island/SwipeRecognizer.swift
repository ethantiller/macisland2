import CoreGraphics

/// A two-finger trackpad swipe, decided from the scroll deltas of one gesture.
enum Swipe: Equatable {
    case down, up, left, right
}

/// Accumulates the scroll deltas of a gesture and reports at most one swipe per gesture.
struct SwipeRecognizer {
    static let verticalThreshold: CGFloat = 24
    static let horizontalThreshold: CGFloat = 60

    private var deltaX: CGFloat = 0
    private var deltaY: CGFloat = 0
    private var didFire = false

    /// `dx` and `dy` are `scrollingDeltaX` and `scrollingDeltaY`; `inverted` is `isDirectionInvertedFromDevice`
    /// (natural scrolling). Both are turned into finger movement, so a swipe down means fingers moving down.
    mutating func add(dx: CGFloat, dy: CGFloat, inverted: Bool, began: Bool) -> Swipe? {
        if began {
            deltaX = 0
            deltaY = 0
            didFire = false
        }
        guard !didFire else { return nil }
        let sign: CGFloat = inverted ? 1 : -1
        deltaX += dx * sign
        deltaY += dy * sign

        let swipe: Swipe?
        if abs(deltaX) >= Self.horizontalThreshold, abs(deltaX) > abs(deltaY) {
            swipe = deltaX < 0 ? .left : .right
        } else if abs(deltaY) >= Self.verticalThreshold, abs(deltaY) > abs(deltaX) {
            swipe = deltaY > 0 ? .down : .up
        } else {
            swipe = nil
        }
        didFire = swipe != nil
        return swipe
    }
}
