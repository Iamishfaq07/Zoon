import Foundation

/// Deterministic, seedable pseudo-random source (SplitMix64) for reproducible
/// statistics -- unlike `SystemRandomNumberGenerator`, the same seed always
/// produces the same sequence, so a bootstrap confidence interval is exactly
/// reproducible in tests and stable for a user revisiting the same finding
/// rather than jittering between app launches.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform double in `range`.
    ///
    /// Computed directly from `next()` rather than via
    /// `Double.random(in:using: &self)` — passing `&self` from inside a mutating
    /// method is an overlapping-access violation.
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        // Top 53 bits give a uniform value in [0, 1).
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
