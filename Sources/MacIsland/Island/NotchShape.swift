import SwiftUI

/// Island outline: a flat top that meets the bezel, concave flares at the top corners like the
/// hardware notch, and continuous (squircle) bottom corners.
struct NotchShape: Shape {
    var topFlare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFlare, bottomRadius) }
        set {
            topFlare = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let flare = min(topFlare, rect.width / 2)
        let body = CGRect(x: rect.minX + flare, y: rect.minY, width: rect.width - 2 * flare, height: rect.height)
        let radius = max(min(bottomRadius, body.width / 2, body.height - flare), 0)

        var path = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: 0,
            style: .continuous
        ).path(in: body)

        // Concave fillets joining each side to the bezel.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: rect.minY + flare),
            control: CGPoint(x: body.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: body.minX, y: rect.minY))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: rect.minY + flare),
            control: CGPoint(x: body.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: body.maxX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}
