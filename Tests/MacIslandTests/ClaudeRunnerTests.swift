import AppKit
import Foundation
import QuartzCore
import Testing

@testable import MacIsland

/// The little runner on the Now tab plays by itself and never hits a cactus.
@MainActor
struct ClaudeRunnerTests {
    @Test func theCritterAlwaysClearsACactusOverItsBody() {
        var jumps = 0
        for step in 0..<6_000 {
            let time = Double(step) * 0.01
            let lift = RunnerScene.lift(at: time, width: 472)
            for x in RunnerScene.cactusXs(at: time, width: 472) where abs(x - RunnerScene.critterX) < 16 {
                #expect(lift >= RunnerScene.cactusHeight, "at \(time)s")
            }
            if lift > 0 { jumps += 1 }
        }
        #expect(jumps > 0, "it does jump")
    }

    @Test func itStaysOnTheGroundBetweenCacti() {
        // A second in, the nearest cactus is still well ahead.
        #expect(RunnerScene.lift(at: 1, width: 472) == 0)
        #expect(RunnerScene.liftedLegs(at: 0, lift: 0) == [0, 2])
        #expect(RunnerScene.liftedLegs(at: 0.13, lift: 0) == [1, 3], "the legs swap as it runs")
        #expect(RunnerScene.liftedLegs(at: 0, lift: 10).isEmpty, "legs straight in the air")
    }

    @Test func theJumpNeverReachesPastTheTopOfItsStrip() {
        // The critter's body is about 19 pt tall; at the top of a jump it must still be inside the strip.
        let bodyHeight: CGFloat = 279 * 30 / 447
        let top = 6 + bodyHeight + RunnerScene.jumpHeight
        #expect(top < Theme.Metrics.runnerHeight, "a taller jump than the strip cut the critter off")
    }

    @Test func theLoopEndsWhereItBeganSoItRepeatsWithoutASeam() {
        let times = RunnerScene.sampleTimes()
        #expect(times.first == 0 && abs((times.last ?? 0) - RunnerScene.loopDuration) < 1e-9)
        #expect(times.count == Int((RunnerScene.loopDuration * 60).rounded()) + 1)
        let first = RunnerScene.lift(at: times[0], width: 472)
        let last = RunnerScene.lift(at: times[times.count - 1], width: 472)
        #expect(abs(first - last) < 0.001)
        #expect(
            RunnerScene.liftedLegs(at: 0, lift: first) == RunnerScene.liftedLegs(at: RunnerScene.loopDuration, lift: last))
    }

    @Test func theGapsMakeAnUnevenBeat() {
        #expect(Set(RunnerScene.gaps).count == RunnerScene.gaps.count)
        let xs = RunnerScene.cactusXs(at: 0, width: 1_000)
        #expect(xs == xs.sorted() && xs.allSatisfy { $0 > -RunnerScene.cactusWidth })
    }

    @Test func theLiveRunnerIsLayersWithLoopingAnimationsAndNoTimer() throws {
        let view = RunnerLayerView()
        view.setFrameSize(NSSize(width: 472, height: Theme.Metrics.runnerHeight))
        view.configure(ink: .white, critter: .orange)
        let root = try #require(view.layer)
        let count = root.sublayers?.count ?? 0
        #expect(count > 0)
        var keys: [String: Int] = [:]
        func walk(_ layer: CALayer) {
            for key in layer.animationKeys() ?? [] {
                keys[key, default: 0] += 1
                #expect(layer.animation(forKey: key)?.repeatCount == .infinity, "\(key) loops by itself")
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        #expect(keys["jump"] == 1 && keys["pose"] == 3 && keys["fly"] == 2 && keys["flap"] == 4)
        #expect((keys["slide"] ?? 0) >= 3, "dashes, cacti and clouds slide")
        // Configured again with the same size and colors, it keeps what it has.
        view.configure(ink: .white, critter: .orange)
        #expect(root.sublayers?.count == count)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderTheLayers() throws {
        let view = RunnerLayerView()
        view.setFrameSize(NSSize(width: 472, height: Theme.Metrics.runnerHeight))
        view.configure(ink: .white, critter: NSColor(Theme.Mark.claude))
        let root = try #require(view.layer)
        let scale = 2
        let width = 472 * scale
        let height = Int(Theme.Metrics.runnerHeight) * scale
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        root.render(in: context)
        let image = try #require(context.makeImage())
        let folder = try #require(ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"])
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("30h-runner-layers.png"))
    }
}
