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

    /// `sampleRate` sets the look-ahead (5 ms) and the release (about 80 ms back to full), so the sound is the same at any rate.
    init(channels: Int, sampleRate: Double) {
        self.channels = max(channels, 1)
        lookahead = max(Int(sampleRate * 0.005), 2)
        // The gain climbs back by this share of what's missing each frame: 1 - e^(-1 / (0.08 s * rate)) is about 12.5 / rate.
        release = Float(1 - exp(-1 / (0.08 * max(sampleRate, 1))))
        delay = [Float](repeating: 0, count: lookahead * self.channels)
        queueFrames = [Int](repeating: 0, count: lookahead + 1)
        queueGains = [Float](repeating: 1, count: lookahead + 1)
    }

    /// Forgets what it has seen: after a stretch with no limiting, so a boost starts clean.
    mutating func reset() {
        for index in delay.indices { delay[index] = 0 }
        delayFrame = 0
        head = 0
        count = 0
        frameNumber = 0
        gain = 1
    }

    /// Fills `output` with `input` times `level`. Up to 1.0 the sound isn't delayed; unity passes samples unchanged. Both hold
    /// `frames * channels` samples and may be the same memory.
    mutating func process(
        _ input: UnsafePointer<Float>, into output: UnsafeMutablePointer<Float>, frames: Int, level: Float
    ) {
        let samples = frames * channels
        if level <= 1 {
            if count != 0 { reset() }
            if level == 1 {
                if UnsafePointer(output) != input { output.update(from: input, count: samples) }
            } else {
                for index in 0..<samples { output[index] = input[index] * max(level, 0) }
            }
            return
        }
        let boost = min(level, Self.maxGain)
        for frame in 0..<frames {
            let base = frame * channels
            // The boosted frame, and the gain it needs to stay inside the ceiling.
            var peak: Float = 0
            for channel in 0..<channels { peak = max(peak, abs(input[base + channel] * boost)) }
            let wanted: Float = peak > Self.ceiling ? Self.ceiling / peak : 1
            push(wanted)
            // Replace the oldest frame in the delay with this one, and play the one it replaces.
            let slot = delayFrame * channels
            let target = min(queueGains[head], 1)
            gain = min(target, gain + (1 - gain) * release)
            for channel in 0..<channels {
                let played = delay[slot + channel]
                delay[slot + channel] = input[base + channel] * boost
                let value = played * gain
                output[base + channel] = min(max(value, -Self.ceiling), Self.ceiling)
            }
            delayFrame = (delayFrame + 1) % lookahead
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
