import Foundation

/// Gain for the Mixer: 0 to 200%. Up to 100% it is a plain multiply. Above it, a look-ahead peak limiter keeps every sample inside
/// ±1.0, so boosting a loud track doesn't clip: the gain it needs to stay inside is found a few milliseconds ahead, and the sound is
/// delayed by that long. Written to run on the audio thread: no allocation, no locks, after `init`.
///
/// Interleaved 32-bit float. One limiter per tap, because it remembers the last few milliseconds.
struct BoostLimiter {
    /// The loudest sample the limiter lets through.
    static let ceiling: Float = 1.0
    /// The most the Mixer boosts.
    static let maxGain: Float = 2.0

    let channels: Int
    /// How far ahead it looks, in frames.
    let lookahead: Int
    private let release: Float

    /// The last `lookahead` frames, delayed so the limiter has seen what is coming.
    private var delay: [Float]
    private var delayFrame = 0
    /// The smallest wanted gain over the look-ahead window, as a monotone queue of (frame number, wanted gain) in a ring.
    private var queueFrames: [Int]
    private var queueGains: [Float]
    private var head = 0
    private var count = 0
    private var frameNumber = 0
    private var gain: Float = 1
    /// The level of the last buffer, so a change is ramped across the next one instead of stepping (a step is a click).
    private var lastLevel: Float?
    /// Whether the limiter is in line. While it is not, the sound is not delayed at all.
    private var isActive = false
    /// While it is in line: 1 plays the direct sound, 0 the limited and delayed one, and in between is a crossfade, so going into or out
    /// of the limiter (the level crossing 100%) never splices 5 ms of sound in or out.
    private var mix: Float = 0
    /// Frames since the limiter went in line; until the delay holds real sound, the direct sound plays.
    private var primed = 0
    /// Whether the direct sound plays while the delay fills: yes when it went in line mid-stream, no for a tap's first buffer.
    private var crossfadesIn = false

    /// `sampleRate` sets the look-ahead (5 ms) and the release (about 80 ms back to full), so the sound is the same at any rate.
    init(channels: Int, sampleRate: Double) {
        self.channels = max(channels, 1)
        lookahead = max(safeInt(sampleRate * 0.005), 2)
        // The gain climbs back by this share of what's missing each frame: 1 - e^(-1 / (0.08 s * rate)) is about 12.5 / rate.
        release = Float(1 - exp(-1 / (0.08 * max(sampleRate, 1))))
        delay = [Float](repeating: 0, count: lookahead * self.channels)
        queueFrames = [Int](repeating: 0, count: lookahead + 1)
        queueGains = [Float](repeating: 1, count: lookahead + 1)
    }

    /// Forgets everything: the limiter is out of line and the next level starts without a ramp.
    mutating func reset() {
        clearWindow()
        lastLevel = nil
        isActive = false
    }

    /// Empties the look-ahead, so a boost starts clean.
    private mutating func clearWindow() {
        for index in delay.indices { delay[index] = 0 }
        delayFrame = 0
        head = 0
        count = 0
        frameNumber = 0
        gain = 1
        primed = 0
    }

    /// Fills `output` with `input` times `level`. Up to 1.0 the sound isn't delayed; unity passes samples unchanged. Both hold
    /// `frames * channels` samples and may be the same memory.
    ///
    /// A level that changed since the last buffer is ramped across this one, frame by frame, so a slider being dragged is smooth. When
    /// the level goes over 100% the limiter comes in line, and the direct sound crossfades into the delayed one over `lookahead`
    /// frames; coming back under, it crossfades out and the limiter leaves line again.
    mutating func process(
        _ input: UnsafePointer<Float>, into output: UnsafeMutablePointer<Float>, frames: Int, level: Float
    ) {
        guard frames > 0 else { return }
        let start = lastLevel ?? level
        let hadHistory = lastLevel != nil
        lastLevel = level
        if !isActive && (level > 1 || start > 1) {
            clearWindow()
            isActive = true
            // A tap's first buffer has nothing before it to cross from: it starts limited, with silence for the look-ahead.
            mix = hadHistory ? 1 : 0
            crossfadesIn = hadHistory
        }
        guard isActive else {
            processDirect(input, into: output, frames: frames, from: start, to: level)
            return
        }
        let step = 1 / Float(lookahead)
        for frame in 0..<frames {
            let base = frame * channels
            let levelNow = start + (level - start) * Float(frame + 1) / Float(frames)
            let boost = min(max(levelNow, 0), Self.maxGain)
            // The boosted frame, and the gain it needs to stay inside the ceiling.
            var peak: Float = 0
            for channel in 0..<channels { peak = max(peak, abs(Self.finite(input[base + channel]) * boost)) }
            let wanted: Float = peak > Self.ceiling ? Self.ceiling / peak : 1
            push(wanted)
            let target = min(queueGains[head], 1)
            gain = min(target, gain + (1 - gain) * release)
            // Direct while the delay is still filling, and once nothing is boosted or limited; limited otherwise.
            let wantsDirect = (crossfadesIn && primed < lookahead) || (levelNow <= 1 && gain >= 0.9999)
            mix = wantsDirect ? min(mix + step, 1) : max(mix - step, 0)
            // Replace the oldest frame in the delay with this one, and play the one it replaces.
            let slot = delayFrame * channels
            for channel in 0..<channels {
                let boosted = Self.finite(input[base + channel]) * boost
                let played = delay[slot + channel]
                delay[slot + channel] = boosted
                let limited = min(max(played * gain, -Self.ceiling), Self.ceiling)
                let direct = min(max(boosted, -Self.ceiling), Self.ceiling)
                output[base + channel] = mix >= 1 ? direct : (mix <= 0 ? limited : direct * mix + limited * (1 - mix))
            }
            delayFrame = (delayFrame + 1) % lookahead
            primed = min(primed + 1, Int.max - 1)
        }
        // Fully direct again, with nothing boosted: out of line, so the sound is not delayed.
        if mix >= 1 && level <= 1 && primed >= lookahead { isActive = false }
    }

    /// A sample that is not a number or is infinite is silence, so it cannot poison the gain.
    @inline(__always) private static func finite(_ sample: Float) -> Float { sample.isFinite ? sample : 0 }

    /// Not in line: the sound times the level, ramped from `start` to `end` over the buffer when they differ.
    private func processDirect(
        _ input: UnsafePointer<Float>, into output: UnsafeMutablePointer<Float>, frames: Int, from start: Float, to end: Float
    ) {
        let samples = frames * channels
        if start == end {
            if end == 1 {
                if UnsafePointer(output) != input { output.update(from: input, count: samples) }
            } else {
                let scale = max(end, 0)
                for index in 0..<samples { output[index] = input[index] * scale }
            }
            return
        }
        for frame in 0..<frames {
            let scale = max(start + (end - start) * Float(frame + 1) / Float(frames), 0)
            for channel in 0..<channels { output[frame * channels + channel] = input[frame * channels + channel] * scale }
        }
    }

    /// Adds a frame's wanted gain to the queue, dropping what has left the window (the played frame and the `lookahead` frames after
    /// it) and what can no longer be the smallest.
    private mutating func push(_ wanted: Float) {
        let capacity = queueFrames.count
        while count > 0, queueFrames[head] < frameNumber - lookahead {
            head = (head + 1) % capacity
            count -= 1
        }
        while count > 0 {
            let last = (head + count - 1) % capacity
            if queueGains[last] >= wanted { count -= 1 } else { break }
        }
        let slot = (head + count) % capacity
        queueFrames[slot] = frameNumber
        queueGains[slot] = wanted
        count += 1
        frameNumber += 1
    }
}
