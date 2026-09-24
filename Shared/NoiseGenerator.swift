import Foundation

/// The generated sleep-noise synthesis, as plain value-type DSP.
///
/// Audit §9.2: this used to run inside `SoundscapeEngine`, which is
/// `@MainActor`, calling `Float.random` and `Int.random` per sample for every
/// five-second buffer -- several hundred thousand system RNG calls competing
/// with the UI. The maths is unchanged; what changed is where it runs (a
/// `NoiseRenderer` actor owns an instance of this) and the random source: a
/// SplitMix64 generator, which is fast, allocation-free and deterministic
/// for a given seed, so a test can pin it.
struct NoiseGenerator: Sendable {

    enum Kind: Sendable {
        case white, pink, brown
    }

    /// SplitMix64 (Steele, Lea & Flood, 2014). Not cryptographic; it only
    /// has to be fast and statistically flat for audio.
    struct Random: Sendable {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in -1..<1 from the top 24 bits.
        mutating func signed() -> Float {
            Float(next() >> 40) / Float(1 << 24) * 2 - 1
        }
    }

    private var random: Random
    // Filter state carried across buffers so filters don't click at seams.
    private var brownState: Float = 0
    private var pinkRows = [Float](repeating: 0, count: 7)
    private var lowpassState: Float = 0

    init(seed: UInt64 = 0x5EED_2026) {
        random = Random(seed: seed)
    }

    /// Renders `frames` stereo samples.
    ///
    /// - Parameter harmonicPresence: 1 leaves the sound unfiltered; lower
    ///   values strip high harmonics as overnight heart rate falls (the
    ///   engine's sleep-onset cue).
    mutating func render(
        _ kind: Kind,
        frames: Int,
        harmonicPresence: Float = 1
    ) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            let white = random.signed()
            var sample: Float
            switch kind {
            case .white:
                sample = white * 0.25
            case .pink:
                // Voss-McCartney: sum of octave-spaced random rows.
                sample = pinkSample(white) * 0.16
            case .brown:
                // Integrated white noise, leaked toward zero so it can't
                // drift into DC offset over a long session.
                brownState = (brownState + white * 0.02) * 0.995
                sample = brownState * 2.4
            }
            sample = max(-1, min(1, sample))
            if harmonicPresence < 0.999 {
                let coefficient = 0.08 + 0.45 * harmonicPresence
                lowpassState += coefficient * (sample - lowpassState)
                sample = lowpassState
            }
            // Slight stereo decorrelation, so the sound sits around the
            // listener rather than as a point inside the head.
            left[frame] = sample
            right[frame] = sample * 0.92 + random.signed() * 0.02
        }
        return (left, right)
    }

    private mutating func pinkSample(_ white: Float) -> Float {
        var sum: Float = 0
        for row in 0..<pinkRows.count {
            // Each row updates half as often as the one before it: with
            // probability 1 / 2^row, the same as `Int.random(in: 0..<(1 << row)) == 0`.
            let mask = (UInt64(1) << UInt64(row)) - 1
            if random.next() & mask == 0 {
                pinkRows[row] = random.signed()
            }
            sum += pinkRows[row]
        }
        return (sum / Float(pinkRows.count)) + white * 0.1
    }
}

/// A recorded bed turned into a loop with no audible join.
///
/// Audit §9.1: the beds were played with `AVAudioPlayer.numberOfLoops = -1`
/// under a comment claiming they were crossfaded at the join. They were not;
/// several files end on a different waveform value from the one they start
/// on, which is an audible click and an identifiable seam every ~87 seconds.
///
/// The loop is the source without its first `c` frames, with its last `c`
/// frames equal-power crossfaded into those first `c`. Wrapping from the
/// loop's end lands on source frame `c`, which is exactly the frame that
/// follows the crossfade's end -- so the join is as continuous as any two
/// adjacent frames of the recording.
enum SeamlessLoop {

    /// Two seconds at 44.1 kHz: long enough that a texture change across
    /// the join is not heard as an event.
    static let defaultCrossfadeSeconds = 2.0

    /// `nil` when the source is too short to loop with that crossfade.
    static func make(_ source: [Float], crossfadeFrames c: Int) -> [Float]? {
        var loop = source
        return makeInPlace(&loop, crossfadeFrames: c) ? loop : nil
    }

    /// The same loop, built in the caller's storage: the tail is crossfaded
    /// in place and the head dropped, so a 90-second bed is never held twice.
    /// Leaves `samples` untouched and returns `false` when it is too short.
    static func makeInPlace(_ samples: inout [Float], crossfadeFrames c: Int) -> Bool {
        let length = samples.count
        guard c > 0, length > 2 * c else { return false }
        for k in 0..<c {
            let t = (Float(k) + 0.5) / Float(c)
            let fadeOut = cos(t * .pi / 2)
            let fadeIn = sin(t * .pi / 2)
            samples[length - c + k] = samples[length - c + k] * fadeOut + samples[k] * fadeIn
        }
        samples.removeFirst(c)
        return true
    }

    /// The step across the join when `samples` is played end to start.
    static func seamStep(_ samples: [Float]) -> Float {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return abs(first - last)
    }

    /// The largest step between adjacent frames anywhere inside `samples` --
    /// what a join has to stay within to be as smooth as the recording.
    static func largestInteriorStep(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var largest: Float = 0
        for i in 1..<samples.count {
            largest = max(largest, abs(samples[i] - samples[i - 1]))
        }
        return largest
    }
}
