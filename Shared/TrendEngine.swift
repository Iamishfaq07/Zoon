import Foundation

/// Detects meaningful changes between two comparable windows of history --
/// "your bedtime shifted 38 minutes later this month" -- rather than leaving
/// the user to notice a slow drift by eyeballing a chart.
///
/// Two rules keep this from turning into daily noise:
///
/// 1. **Non-overlapping windows.** The current window is compared against
///    the window immediately before it, never against itself.
/// 2. **A minimum effect per metric**, tuned to how noisy that metric
///    naturally is night to night -- HRV needs a bigger relative move to
///    mean anything than a stable metric like efficiency does.
enum TrendEngine {

    struct Result: Identifiable, Hashable {
        let metric: Metric
        let currentMedian: Double
        let previousMedian: Double
        let windowNights: Int
        var id: String { metric.rawValue }

        var delta: Double { currentMedian - previousMedian }
        var isImprovement: Bool { metric.higherIsBetter ? delta > 0 : delta < 0 }

        var sentence: String {
            let direction = delta > 0 ? "increased" : "decreased"
            return "Your \(metric.label) \(direction) by \(metric.formattedMagnitude(abs(delta))) over the last \(windowNights) nights."
        }
    }

    enum Metric: String, CaseIterable, Hashable {
        case duration, bedtime, hrv, restingHeartRate, efficiency, sleepDebt

        var label: String {
            switch self {
            case .duration: "average sleep duration"
            case .bedtime: "bedtime"
            case .hrv: "HRV"
            case .restingHeartRate: "resting heart rate"
            case .efficiency: "sleep efficiency"
            case .sleepDebt: "sleep debt"
            }
        }

        var higherIsBetter: Bool {
            switch self {
            case .duration, .hrv, .efficiency: true
            case .bedtime, .restingHeartRate, .sleepDebt: false
            }
        }

        /// Minimum absolute or relative change before a shift is reported at
        /// all -- see the type doc for why this varies per metric.
        fileprivate func clearsThreshold(_ delta: Double, previousMedian: Double) -> Bool {
            switch self {
            case .duration: abs(delta) >= 15
            case .bedtime: abs(delta) >= 20
            case .hrv: previousMedian > 0 && abs(delta / previousMedian) >= 0.10
            case .restingHeartRate: abs(delta) >= 2
            case .efficiency: abs(delta) >= 3
            case .sleepDebt: abs(delta) >= 20
            }
        }

        fileprivate func formattedMagnitude(_ magnitude: Double) -> String {
            switch self {
            case .duration, .bedtime, .sleepDebt:
                SleepNightFeatures.formatMinutes(magnitude)
            case .hrv, .restingHeartRate:
                String(format: "%.0f", magnitude) + (self == .hrv ? " ms" : " bpm")
            case .efficiency:
                String(format: "%.0f%%", magnitude)
            }
        }

        fileprivate func value(from night: SleepNightFeatures) -> Double? {
            switch self {
            case .duration: night.timeAsleepMinutes
            case .bedtime: Statistics.circularMinutesFromMidnight(night.bedtime)
            case .hrv: night.avgHRV
            case .restingHeartRate: night.restingHeartRate
            case .efficiency: night.sleepEfficiencyPercent
            case .sleepDebt: night.sleepDebtMinutes14Day
            }
        }
    }

    /// - Parameter windowNights: size of each of the two compared windows.
    ///   30 matches the spec's "six weeks" example when nights are logged
    ///   roughly daily; kept smaller by default so it also produces results
    ///   for someone earlier in their history.
    static func detect(nights: [SleepNightFeatures], windowNights: Int = 14) -> [Result] {
        let sorted = nights.sorted { $0.date < $1.date }
        guard sorted.count >= windowNights * 2 else { return [] }

        let current = Array(sorted.suffix(windowNights))
        let previous = Array(sorted.suffix(windowNights * 2).prefix(windowNights))

        var results: [Result] = []
        for metric in Metric.allCases {
            let currentValues = current.compactMap(metric.value)
            let previousValues = previous.compactMap(metric.value)
            guard currentValues.count >= windowNights / 2, previousValues.count >= windowNights / 2,
                  let currentMedian = Statistics.median(currentValues),
                  let previousMedian = Statistics.median(previousValues) else { continue }

            let delta = currentMedian - previousMedian
            guard metric.clearsThreshold(delta, previousMedian: previousMedian) else { continue }

            results.append(Result(
                metric: metric,
                currentMedian: currentMedian,
                previousMedian: previousMedian,
                windowNights: windowNights
            ))
        }

        return results.sorted { abs($0.delta / max(abs($0.previousMedian), 1)) > abs($1.delta / max(abs($1.previousMedian), 1)) }
    }
}
