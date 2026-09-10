import Foundation

/// A compact, explainable summary of a person's recent sleep signature.
/// Values are normalized to 0...1 so the view can render them consistently.
struct SleepFingerprint: Equatable {
    let sampleCount: Int
    let timingStability: Double
    let durationStability: Double
    let continuity: Double
    let bodySignalStability: Double
    /// False when fewer than two nights carried an HRV reading. In that
    /// case `bodySignalStability` is a placeholder, not a reading: there is
    /// no dispersion to measure, and a low value here must not be shown as
    /// "your body signals are unstable". Consumers should hide or label the
    /// metric when this is false rather than render the number.
    let bodySignalStabilityIsMeasured: Bool

    static func make(from nights: [SleepNightFeatures], days: Int) -> SleepFingerprint? {
        let sample = Array(nights.suffix(days))
        guard sample.count >= 3 else { return nil }

        let bedtimes = sample.map { minutesSinceMidnight($0.bedtime, timeZone: $0.timeZone) }
        let timingMAD = Statistics.circularMedianAbsoluteDeviation(bedtimes) ?? 0
        let durations = sample.map(\.timeAsleepMinutes)
        let durationMAD = Statistics.medianAbsoluteDeviation(durations) ?? 0
        let durationMedian = max(1, Statistics.median(durations) ?? 0)

        let efficiency = sample.map(\.sleepEfficiencyPercent).filter { $0.isFinite }
        let continuity = min(1, max(0, (Statistics.median(efficiency.isEmpty ? [0] : efficiency) ?? 0) / 100))

        let body = sample.compactMap { night -> Double? in
            guard let value = night.avgHRV, value.isFinite, value > 0 else { return nil }
            return value
        }
        let bodyIsMeasured = body.count >= 2
        let bodyMAD = bodyIsMeasured ? (Statistics.medianAbsoluteDeviation(body) ?? 0) / max(1, Statistics.median(body) ?? 0) : 0.5

        return SleepFingerprint(
            sampleCount: sample.count,
            timingStability: stability(fromMAD: timingMAD, scale: 90),
            durationStability: stability(fromMAD: durationMAD, scale: max(30, durationMedian * 0.35)),
            continuity: continuity,
            bodySignalStability: stability(fromMAD: bodyMAD, scale: 0.35),
            bodySignalStabilityIsMeasured: bodyIsMeasured
        )
    }

    private static func stability(fromMAD mad: Double, scale: Double) -> Double {
        min(1, max(0, 1 - mad / max(0.001, scale)))
    }

    private static func minutesSinceMidnight(_ date: Date, timeZone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}
