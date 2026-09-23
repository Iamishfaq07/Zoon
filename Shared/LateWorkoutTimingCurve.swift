import Foundation

/// Personal association between workout-end timing and the following night.
///
/// Not a universal late-exercise rule. Nights without a workout timestamp
/// are skipped, not treated as zero. Wording stays observational.
enum LateWorkoutTimingCurve {

    static let minimumNightsPerGroup = 5
    /// Hours before bed that count as late for this person's curve.
    static let lateHours = 2.0
    /// Hours before bed that count as the comparison group.
    static let earlierHours = 3.0
    /// A duration difference smaller than this is "little observed difference".
    static let practicalDifferenceMinutes = 15.0

    struct Finding: Equatable, Sendable {
        let sentence: String
        let sampleCount: Int
        let lateCount: Int
        let earlierCount: Int
        let confidence: String
        let limitation: String
    }

    static func learn(nights: [SleepNightFeatures]) -> Finding? {
        let dated = nights.filter { $0.lastWorkoutHoursBeforeBed != nil }
        let late = dated.filter { ($0.lastWorkoutHoursBeforeBed ?? 99) <= lateHours }
        let earlier = dated.filter { ($0.lastWorkoutHoursBeforeBed ?? 0) >= earlierHours }
        guard late.count >= minimumNightsPerGroup,
              earlier.count >= minimumNightsPerGroup else { return nil }

        let lateAsleep = mean(late.map(\.timeAsleepMinutes))
        let earlierAsleep = mean(earlier.map(\.timeAsleepMinutes))
        let delta = earlierAsleep - lateAsleep
        let sampleCount = late.count + earlier.count
        let confidence: String
        if sampleCount >= 16 {
            confidence = "Moderate — enough nights to compare, still a small personal set"
        } else {
            confidence = "Limited — the bands just clear the minimum"
        }
        let limitation = "This is an association in your recorded nights, not proof that the workout caused the sleep. Load, caffeine, and schedule are not held constant."

        let sentence: String
        if abs(delta) < practicalDifferenceMinutes {
            sentence = "Workouts ending within ~\(Int(lateHours)) hours of bedtime have not shown a meaningful sleep-duration difference from earlier sessions in your log."
        } else if delta > 0 {
            sentence = "Workouts ending within ~\(Int(lateHours)) hours of bedtime have been associated with about \(SleepNightFeatures.formatMinutes(delta)) less sleep than earlier sessions for you."
        } else {
            sentence = "Workouts ending within ~\(Int(lateHours)) hours of bedtime have been associated with about \(SleepNightFeatures.formatMinutes(-delta)) more sleep than earlier sessions for you."
        }

        return Finding(
            sentence: sentence,
            sampleCount: sampleCount,
            lateCount: late.count,
            earlierCount: earlier.count,
            confidence: confidence,
            limitation: limitation
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
