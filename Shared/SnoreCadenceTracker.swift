import Foundation

/// Temporal model for snoring bursts.
///
/// The previous detector required 3+ bursts while dropping anything older
/// than ~6 seconds. A valid 5-second cadence (burst at 0s, 5s, 10s) could
/// never retain three timestamps at once, so slower snoring never counted.
///
/// History is 18 seconds. A run of three or more bursts whose consecutive
/// gaps sit in 1.2...6 seconds is snoring; a single cough or slam is not.
struct SnoreCadenceTracker: Equatable, Sendable {
    var burstTimestamps: [TimeInterval] = []

    let minBurstGap: TimeInterval
    let maxBurstGap: TimeInterval
    let historyWindow: TimeInterval
    let minimumBursts: Int

    init(
        minBurstGap: TimeInterval = 1.2,
        maxBurstGap: TimeInterval = 6.0,
        historyWindow: TimeInterval = 18.0,
        minimumBursts: Int = 3
    ) {
        self.minBurstGap = minBurstGap
        self.maxBurstGap = maxBurstGap
        self.historyWindow = historyWindow
        self.minimumBursts = minimumBursts
    }

    /// Register a leading-edge burst at session-relative time `t`.
    mutating func registerBurst(at t: TimeInterval) {
        prune(now: t)
        if let last = burstTimestamps.last {
            let gap = t - last
            if gap < minBurstGap { return }
            if gap > maxBurstGap * 2 {
                // Sustained break: start a new run rather than bridging
                // unrelated noises into a fake cadence.
                burstTimestamps = [t]
                return
            }
        }
        burstTimestamps.append(t)
        prune(now: t)
    }

    mutating func prune(now t: TimeInterval) {
        let cutoff = t - historyWindow
        burstTimestamps.removeAll { $0 < cutoff }
    }

    /// True when the retained bursts form a snore-like cadence.
    func isSnoring(at t: TimeInterval) -> Bool {
        let cutoff = t - historyWindow
        let recent = burstTimestamps.filter { $0 >= cutoff }
        guard recent.count >= minimumBursts else { return false }
        let gaps = zip(recent.dropFirst(), recent).map { $0.0 - $0.1 }
        let accepted = gaps.filter { (minBurstGap...maxBurstGap).contains($0) }
        return accepted.count >= minimumBursts - 1
    }
}
