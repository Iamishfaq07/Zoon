import Foundation

/// A compact, explainable summary of a person's recent sleep signature.
/// Values are normalized to 0...1 so the view can render them consistently.
struct SleepFingerprint: Equatable {
    let sampleCount: Int
    let timingStability: Double
    let durationStability: Double
    let continuity: Double
    let bodySignalStability: Double

    static func make(from nights: [SleepNightFeatures], days: Int) -> SleepFingerprint? {
        let sample = Array(nights.suffix(days))
        guard sample.count >= 3 else { return nil }

        let bedtimes = sample.map { minutesSinceMidnight($0.bedtime) }
        let timingMAD = circularMAD(bedtimes)
        let durations = sample.map(\.timeAsleepMinutes)
        let durationMAD = Statistics.medianAbsoluteDeviation(durations) ?? 0
        let durationMedian = max(1, Statistics.median(durations) ?? 0)

        let efficiency = sample.map(\.sleepEfficiencyPercent).filter { $0.isFinite }
        let continuity = min(1, max(0, (Statistics.median(efficiency.isEmpty ? [0] : efficiency) ?? 0) / 100))

        let body = sample.compactMap { night -> Double? in
            guard let value = night.avgHRV, value.isFinite, value > 0 else { return nil }
            return value
        }
        let bodyMAD = body.count >= 2 ? (Statistics.medianAbsoluteDeviation(body) ?? 0) / max(1, Statistics.median(body) ?? 0) : 0.5

        return SleepFingerprint(
            sampleCount: sample.count,
            timingStability: stability(fromMAD: timingMAD, scale: 90),
            durationStability: stability(fromMAD: durationMAD, scale: max(30, durationMedian * 0.35)),
            continuity: continuity,
            bodySignalStability: stability(fromMAD: bodyMAD, scale: 0.35)
        )
    }

    private static func stability(fromMAD mad: Double, scale: Double) -> Double {
        min(1, max(0, 1 - mad / max(0.001, scale)))
    }

    private static func minutesSinceMidnight(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private static func circularMAD(_ values: [Double]) -> Double {
        guard let centre = values.sorted().dropFirst(max(0, values.count / 2 - 1)).first else { return 0 }
        let distances = values.map { raw -> Double in
            let delta = abs(raw - centre).truncatingRemainder(dividingBy: 1440)
            return min(delta, 1440 - delta)
        }
        return Statistics.medianAbsoluteDeviation(distances) ?? 0
    }
}
