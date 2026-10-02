import SwiftUI

/// The mark of the agent working: Claude Code's pixel critter in its own orange, Codex's cloud in white with its prompt cut out. Drawn
/// as vector shapes in a square of `size`, like `Glyph`, so it sits in the same slots. DESIGN lists the two as the exceptions to "no
/// logos".
struct AgentMark: View {
    let agent: AgentKind
    var size: CGFloat = Theme.Metrics.glyphSlot

    var body: some View {
        Group {
            switch agent {
            case .claudeCode:
                ClaudeMarkShape().fill(Theme.Mark.claude)
            case .codex:
                CodexMarkShape().fill(Theme.Palette.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(agent.rawValue)
    }
}

/// The marks of the agents working, one per kind (at most two), a few points apart.
struct AgentMarks: View {
    let tasks: [AgentTask]
    var size: CGFloat = Theme.Metrics.glyphSlot

    private var kinds: [AgentKind] { AgentKind.allCases.filter { kind in tasks.contains { $0.agent == kind } } }

    var body: some View {
        HStack(spacing: Theme.Metrics.agentMarkGap) {
            ForEach(kinds) { AgentMark(agent: $0, size: size) }
        }
    }
}

/// The critter, in its 447 by 279 box scaled to the width of the square: a body, arms, four legs, and two eyes cut out.
struct ClaudeMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 447
        let height = 279 * scale
        let origin = CGPoint(x: rect.minX, y: rect.midY - height / 2)
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            Path(CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale))
        }
        var solid = box(56, 0, 334, 225).union(box(0, 112, 447, 55))
        for x: CGFloat in [84, 139, 280, 335] { solid = solid.union(box(x, 225, 27, 54)) }
        return solid.subtracting(box(112, 57, 27, 54)).subtracting(box(307, 57, 27, 54))
    }
}

/// The flower-shaped cloud with a `>_` prompt cut out of it.
struct CodexMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        var blob = circle(center.x, center.y, 0.32 * w)
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            blob = blob.union(
                circle(
                    center.x + CGFloat(cos(angle)) * 0.26 * w, center.y + CGFloat(sin(angle)) * 0.26 * w, 0.24 * w))
        }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * w) }
        var prompt = Path()
        prompt.move(to: point(0.27, 0.35))
        prompt.addLine(to: point(0.37, 0.50))
        prompt.addLine(to: point(0.27, 0.65))
        prompt.move(to: point(0.51, 0.65))
        prompt.addLine(to: point(0.76, 0.65))
        let cut = prompt.strokedPath(StrokeStyle(lineWidth: 0.07 * w, lineCap: .round, lineJoin: .round))
        return blob.subtracting(cut)
    }
}
