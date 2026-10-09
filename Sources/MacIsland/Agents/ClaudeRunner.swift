import AppKit
import SwiftUI

/// Where everything is in the runner, as a plain function of time, so it is tested without drawing. One loop is `loopDuration`
/// long and ends exactly where it began, so it repeats without a seam.
enum RunnerScene {
    /// Points per second the ground goes by.
    static let speed: Double = 150
    /// Where the critter stands, from the left.
    static let critterX: CGFloat = 36
    /// The space after each cactus before the next, so they never come at an even beat.
    static let gaps: [Double] = [210, 280, 190, 340]
    /// How long a jump lasts, and how high it goes, in points.
    static let jumpTime: Double = 0.55
    static let jumpHeight: CGFloat = 20
    static let cactusWidth: CGFloat = 12
    static let cactusHeight: CGFloat = 15
    /// How many times a second the legs swap.
    static let strideRate: Double = 10

    static var period: Double { gaps.reduce(0, +) }
    /// One trip of the ground by: the cacti are in the same places again after this many seconds.
    static var loopDuration: Double { period / speed }

    /// Where each cactus is along the ground, from the first to the last of one period.
    static var cactusPositions: [Double] {
        var along = 0.0
        return gaps.map { gap in
            along += gap
            return along
        }
    }

    /// Where each cactus is on screen at `time`, left to right, as far as `width`.
    static func cactusXs(at time: Double, width: CGFloat) -> [CGFloat] {
        let offset = speed * time
        let cycle = safeInt((offset / period).rounded(.down))
        var xs: [CGFloat] = []
        for round in (cycle - 1)...(cycle + 2) {
            for position in cactusPositions {
                let x = Double(critterX) + position + Double(round) * period - offset
                if x > -Double(cactusWidth) && x < Double(width) { xs.append(CGFloat(x)) }
            }
        }
        return xs.sorted()
    }

    /// How far off the ground the critter is: it jumps over each cactus as it arrives, and never hits one.
    static func lift(at time: Double, width: CGFloat) -> CGFloat {
        var best: CGFloat = 0
        for x in cactusXs(at: time, width: width + 200) {
            let toArrive = Double(x - critterX) / speed
            guard abs(toArrive) < jumpTime / 2 else { continue }
            let progress = 0.5 - toArrive / jumpTime
            best = max(best, jumpHeight * CGFloat(4 * progress * (1 - progress)))
        }
        return best
    }

    /// Which legs are up: none in the air, and two and two on the ground, swapping.
    static func liftedLegs(at time: Double, lift: CGFloat) -> Set<Int> {
        if lift > 0.5 { return [] }
        return safeInt((time * strideRate).rounded(.down)) % 2 == 0 ? [0, 2] : [1, 3]
    }

    /// The loop sampled 60 times a second, first to last (the last is the first again): what the layers' keyframes are made of.
    static func sampleTimes(framesPerSecond: Double = 60) -> [Double] {
        let count = safeInt((loopDuration * framesPerSecond).rounded())
        return (0...count).map { Double($0) / Double(count) * loopDuration }
    }
}

/// A small Claude critter running along a line, jumping over cacti like the browser's dinosaur game, by itself, under clouds and
/// birds. Decoration for the Now tab while nothing is running. It is Core Animation: the whole loop is set up once and the render
/// server plays it, so it costs the app no work per frame (like the sound bars), and it exists only while its tab shows. Held still,
/// in SwiftUI, for snapshots and under Reduce Motion.
struct ClaudeRunnerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.islandSurface) private var surface

    var body: some View {
        Group {
            if isSnapshot || reduceMotion {
                StillRunner()
            } else {
                LiveRunner(ink: surface == .glass ? .labelColor : .white, critter: NSColor(Theme.Mark.claude))
            }
        }
        .frame(height: Theme.Metrics.runnerHeight)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: Shapes (unit-sized, shared by the layers and the still picture)

/// A pixel cactus: a stem with an arm up on each side.
struct PixelCactus: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 12
        let sy = rect.height / 15
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            Path(CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: w * sx, height: h * sy))
        }
        var path = box(4, 0, 4, 15)
        path.addPath(box(0, 5, 3, 2))
        path.addPath(box(0, 3, 2, 4))
        path.addPath(box(9, 4, 3, 2))
        path.addPath(box(10, 2, 2, 4))
        return path
    }
}

/// A flat pixel cloud: a long bank with two humps.
struct PixelCloud: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 26
        let sy = rect.height / 8
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            Path(CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: w * sx, height: h * sy))
        }
        var path = box(2, 5, 22, 3)
        path.addPath(box(6, 2, 8, 3))
        path.addPath(box(10, 0, 5, 2))
        path.addPath(box(16, 3, 6, 2))
        return path
    }
}

/// A pixel bird in flight, wings up or down.
struct PixelBird: Shape {
    var wingsUp: Bool

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 16
        let sy = rect.height / 12
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            Path(CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: w * sx, height: h * sy))
        }
        // Body, head, beak, tail.
        var path = box(3, 6, 9, 3)
        path.addPath(box(11, 4, 3, 3))
        path.addPath(box(14, 5, 2, 1))
        path.addPath(box(0, 7, 3, 1))
        if wingsUp {
            path.addPath(box(5, 2, 4, 4))
            path.addPath(box(7, 0, 3, 3))
        } else {
            path.addPath(box(5, 9, 4, 3))
            path.addPath(box(3, 10, 3, 2))
        }
        return path
    }
}

// MARK: The still picture

private struct StillRunner: View {
    private let critter: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let ground = proxy.size.height - 6
            // The legs' bottom sits 24.4 pt below the top of the critter's square.
            let legsBottom = critter / 2 + (279 * critter / 447) / 2
            ZStack(alignment: .topLeading) {
                PixelCloud().fill(Theme.Palette.fill).frame(width: 52, height: 16).offset(x: 90, y: 6)
                PixelCloud().fill(Theme.Palette.fill).frame(width: 40, height: 12).offset(x: 300, y: 14)
                PixelBird(wingsUp: true).fill(Theme.Palette.tertiary).frame(width: 16, height: 12).offset(x: 220, y: 10)
                Rectangle().fill(Theme.Palette.fillHover).frame(width: proxy.size.width, height: 1).offset(y: ground)
                PixelCactus()
                    .fill(Theme.Palette.tertiary)
                    .frame(width: RunnerScene.cactusWidth, height: RunnerScene.cactusHeight)
                    .offset(x: 170, y: ground - RunnerScene.cactusHeight + 1)
                ClaudeMarkShape(liftedLegs: [0, 2])
                    .fill(Theme.Mark.claude)
                    .frame(width: critter, height: critter)
                    .offset(x: RunnerScene.critterX - critter / 2, y: ground - legsBottom + 1)
            }
        }
    }
}

// MARK: The live one, in Core Animation

private struct LiveRunner: NSViewRepresentable {
    let ink: NSColor
    let critter: NSColor

    func makeNSView(context: Context) -> RunnerLayerView { RunnerLayerView() }

    func updateNSView(_ view: RunnerLayerView, context: Context) {
        view.configure(ink: ink, critter: critter)
    }
}

/// The scene as layers, each with a looping animation added once and then left to the render server: the ground dashes, the cacti, the
/// clouds and the birds slide, the critter's height and legs follow the loop sampled by `RunnerScene`, and the birds' wings flap.
/// Layer-hosting, so AppKit leaves the layers and their animations alone.
final class RunnerLayerView: NSView {
    private var builtFor: (size: CGSize, ink: NSColor, critter: NSColor)?

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        layer?.masksToBounds = true
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // The island's resize changes the size every frame, and a rebuild makes every shape and animation again: at most one in a
        // tenth of a second while it moves, and a last one when it stops.
        let since = Date().timeIntervalSince(lastRebuild)
        if builtFor == nil || since >= 0.1 {
            rebuildIfNeeded()
        } else if !rebuildScheduled {
            rebuildScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.1 - since)) { [weak self] in
                guard let self else { return }
                rebuildScheduled = false
                rebuildIfNeeded()
            }
        }
    }

    private var lastRebuild = Date.distantPast
    private var rebuildScheduled = false

    func configure(ink: NSColor, critter: NSColor) {
        if let built = builtFor, built.ink == ink, built.critter == critter { return }
        pending = (ink, critter)
        rebuildIfNeeded()
    }

    private var pending: (ink: NSColor, critter: NSColor)?

    private func rebuildIfNeeded() {
        guard let colors = pending, bounds.width > 0, bounds.height > 0, let root = layer else { return }
        if let built = builtFor, built.size == bounds.size, built.ink == colors.ink, built.critter == colors.critter { return }
        builtFor = (bounds.size, colors.ink, colors.critter)
        lastRebuild = Date()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        build(into: root, size: bounds.size, ink: colors.ink, critter: colors.critter)
        CATransaction.commit()
    }

    // MARK: Building

    private func build(into root: CALayer, size: CGSize, ink: NSColor, critter: NSColor) {
        let ground: CGFloat = 6
        addClouds(to: root, size: size, color: ink.withAlphaComponent(0.12))
        addBirds(to: root, size: size, color: ink.withAlphaComponent(0.38))
        addGround(to: root, size: size, ground: ground, line: ink.withAlphaComponent(0.2), dash: ink.withAlphaComponent(0.12))
        addCacti(to: root, ground: ground, color: ink.withAlphaComponent(0.38))
        addCritter(to: root, size: size, ground: ground, color: critter)
    }

    /// A shape layer for a SwiftUI shape drawn in a box of `size`, turned over because layers count up from the bottom.
    private func shapeLayer(_ shape: some Shape, size: CGSize, color: NSColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.anchorPoint = .zero
        var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -size.height)
        layer.path = shape.path(in: CGRect(origin: .zero, size: size)).cgPath.copy(using: &flip)
        layer.fillColor = color.cgColor
        return layer
    }

    private func slide(by distance: CGFloat, over duration: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -distance
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    private func addGround(to root: CALayer, size: CGSize, ground: CGFloat, line: NSColor, dash: NSColor) {
        let spacing: CGFloat = 46
        let dashes = CALayer()
        dashes.frame = CGRect(x: 0, y: 0, width: size.width + spacing, height: size.height)
        var x: CGFloat = 0
        while x < size.width + spacing {
            let mark = CALayer()
            mark.backgroundColor = dash.cgColor
            mark.frame = CGRect(x: x, y: ground - 5, width: 8, height: 1)
            dashes.addSublayer(mark)
            x += spacing
        }
        dashes.add(slide(by: spacing, over: Double(spacing) / RunnerScene.speed), forKey: "slide")
        root.addSublayer(dashes)

        let rule = CALayer()
        rule.backgroundColor = line.cgColor
        rule.frame = CGRect(x: 0, y: ground, width: size.width, height: 1)
        root.addSublayer(rule)
    }

    private func addCacti(to root: CALayer, ground: CGFloat, color: NSColor) {
        let strip = CALayer()
        strip.frame = CGRect(x: RunnerScene.critterX, y: 0, width: 1, height: 1)
        let cactus = CGSize(width: RunnerScene.cactusWidth, height: RunnerScene.cactusHeight)
        for round in -1...1 {
            for position in RunnerScene.cactusPositions {
                let layer = shapeLayer(PixelCactus(), size: cactus, color: color)
                layer.position = CGPoint(x: position + Double(round) * RunnerScene.period, y: ground - 1)
                strip.addSublayer(layer)
            }
        }
        strip.add(slide(by: CGFloat(RunnerScene.period), over: RunnerScene.loopDuration), forKey: "slide")
        root.addSublayer(strip)
    }

    private func addClouds(to root: CALayer, size: CGSize, color: NSColor) {
        let loop: CGFloat = 600
        let strip = CALayer()
        strip.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clouds: [(x: CGFloat, fromTop: CGFloat, width: CGFloat, height: CGFloat)] = [
            (30, 6, 52, 16), (210, 16, 40, 12), (390, 8, 60, 18),
        ]
        for round in 0...1 {
            for cloud in clouds {
                let layer = shapeLayer(PixelCloud(), size: CGSize(width: cloud.width, height: cloud.height), color: color)
                layer.position = CGPoint(x: cloud.x + CGFloat(round) * loop, y: size.height - cloud.fromTop - cloud.height)
                strip.addSublayer(layer)
            }
        }
        // Slower than the ground, so they sit far away.
        strip.add(slide(by: loop, over: Double(loop) / 24), forKey: "slide")
        root.addSublayer(strip)
    }

    private func addBirds(to root: CALayer, size: CGSize, color: NSColor) {
        let bird = CGSize(width: 16, height: 12)
        // Each bird crosses at its own height and its own rhythm, so they never line up.
        for (index, flight) in [(fromTop: 12.0, cycle: 11.0, delay: 3.0), (fromTop: 26.0, cycle: 17.0, delay: 9.0)].enumerated() {
            let holder = CALayer()
            holder.bounds = CGRect(origin: .zero, size: bird)
            holder.anchorPoint = .zero
            let y = size.height - CGFloat(flight.fromTop) - bird.height
            holder.position = CGPoint(x: size.width + 30, y: y)
            let up = shapeLayer(PixelBird(wingsUp: true), size: bird, color: color)
            let down = shapeLayer(PixelBird(wingsUp: false), size: bird, color: color)
            holder.addSublayer(up)
            holder.addSublayer(down)

            // The wings: one pose, then the other, a few times a second.
            for (layer, values) in [(up, [1, 1, 0, 0, 1]), (down, [0, 0, 1, 1, 0])] as [(CAShapeLayer, [Double])] {
                let flap = CAKeyframeAnimation(keyPath: "opacity")
                flap.values = values
                flap.keyTimes = [0, 0.48, 0.52, 0.98, 1]
                flap.duration = 0.4
                flap.repeatCount = .infinity
                flap.isRemovedOnCompletion = false
                layer.add(flap, forKey: "flap")
            }

            // The flight: across once, then out of sight until its turn comes round.
            let crossing = Double(size.width + 60) / 120
            let fly = CAKeyframeAnimation(keyPath: "position.x")
            fly.values = [size.width + 30, -30, -30]
            fly.keyTimes = [0, NSNumber(value: crossing / flight.cycle), 1]
            fly.duration = flight.cycle
            fly.timeOffset = flight.delay + Double(index)
            fly.repeatCount = .infinity
            fly.isRemovedOnCompletion = false
            holder.add(fly, forKey: "fly")
            root.addSublayer(holder)
        }
    }

    private func addCritter(to root: CALayer, size: CGSize, ground: CGFloat, color: NSColor) {
        let side: CGFloat = 30
        // The legs' bottom is 24.4 pt below the top of the critter's square: stand it on the line.
        let legsBottom = side / 2 + (279 * side / 447) / 2
        let group = CALayer()
        group.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        group.anchorPoint = .zero
        group.position = CGPoint(x: RunnerScene.critterX - side / 2, y: ground - (side - legsBottom) + 1)
        let poses: [Set<Int>] = [[0, 2], [1, 3], []]
        let layers = poses.map { shapeLayer(ClaudeMarkShape(liftedLegs: $0), size: CGSize(width: side, height: side), color: color) }
        layers.forEach { group.addSublayer($0) }
        root.addSublayer(group)

        let times = RunnerScene.sampleTimes()
        let width = size.width
        let lifts = times.map { RunnerScene.lift(at: $0, width: width) }
        let keyTimes = times.map { NSNumber(value: $0 / RunnerScene.loopDuration) }

        let jump = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jump.values = lifts.map { Double($0) }
        jump.keyTimes = keyTimes
        jump.duration = RunnerScene.loopDuration
        jump.calculationMode = .linear
        jump.repeatCount = .infinity
        jump.isRemovedOnCompletion = false
        group.add(jump, forKey: "jump")

        for (index, layer) in layers.enumerated() {
            let pose = CAKeyframeAnimation(keyPath: "opacity")
            pose.values = zip(times, lifts).map { time, lift in
                RunnerScene.liftedLegs(at: time, lift: lift) == poses[index] ? 1.0 : 0.0
            }
            pose.keyTimes = keyTimes
            pose.duration = RunnerScene.loopDuration
            pose.calculationMode = .linear
            pose.repeatCount = .infinity
            pose.isRemovedOnCompletion = false
            layer.opacity = index == 0 ? 1 : 0
            layer.add(pose, forKey: "pose")
        }
    }
}
