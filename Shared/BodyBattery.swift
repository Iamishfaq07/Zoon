import Foundation

/// A 0–100 energy reserve that charges while you rest and drains as you spend.
///
/// Garmin's Body Battery, reimplemented. It's the most *legible* metric in this
/// whole app: everyone understands a battery. Where recovery is a verdict
/// delivered once each morning, this is a running balance you can watch move,
/// and it makes the cost of a bad night visible in a way a percentage doesn't.
///
/// ## The model
///
/// Start from the overnight charge (driven by recovery quality and sleep
/// duration), then walk the day hour by hour:
///
/// - **Drain** scales with heart rate above resting. Sitting still costs almost
///   nothing; a hard hour costs a lot.
/// - **Charge** happens when heart rate sits at or near resting while awake —
///   genuine rest, not just absence of exercise.
///
/// Deliberately *not* a simulation of anything physiological. It's a legible
/// accounting model whose inputs are all things HealthKit will actually give us.
struct BodyBattery: Codable, Hashable, Sendable {

    /// Hourly samples across the day, oldest first.
    let points: [Point]
    /// Level right now (or at the last sample).
    let current: Int
    /// Level at wake — what the night bought you.
    let morningPeak: Int
    /// Lowest point reached today.
    let dayLow: Int

    struct Point: Codable, Hashable, Sendable, Identifiable {
        let date: Date
        let level: Double
        /// Net change over this hour. Negative = drain.
        let delta: Double
        var id: Date { date }
        var isCharging: Bool { delta > 0 }
    }

    static let empty = BodyBattery(points: [], current: 0, morningPeak: 0, dayLow: 0)

    // MARK: - Build

    /// Charge banked overnight, 0–100.
    ///
    /// Recovery quality dominates: eight hours of fragmented sleep after a hard
    /// day genuinely does not refill the tank, and a model that paid out purely
    /// on hours in bed would say it did.
    static func overnightCharge(recoveryPercent: Int, sleepPerformance: Double) -> Double {
        let recovery = Double(recoveryPercent) / 100
        let sleep = min(1, sleepPerformance / 100)
        // 25 floor so a terrible night still leaves something to spend —
        // a zero would be both wrong and useless.
        return 25 + (recovery * 0.6 + sleep * 0.4) * 75
    }

    /// Builds the day's curve.
    ///
    /// - Parameters:
    ///   - startLevel: level at wake, from `overnightCharge`.
    ///   - hourlyHeartRate: mean HR per hour, oldest first. Hours with no
    ///     coverage should be omitted, not zero-filled — a missing hour is not
    ///     a resting hour.
    ///   - restingHeartRate: the user's own resting rate, the drain threshold.
    ///   - maxHeartRate: for scaling; pass an age-derived estimate if unknown.
    static func build(
        startLevel: Double,
        wakeTime: Date,
        hourlyHeartRate: [(date: Date, bpm: Double)],
        restingHeartRate: Double,
        maxHeartRate: Double
    ) -> BodyBattery {

        guard !hourlyHeartRate.isEmpty else {
            let level = Int(startLevel.rounded())
            return BodyBattery(
                points: [Point(date: wakeTime, level: startLevel, delta: 0)],
                current: level,
                morningPeak: level,
                dayLow: level
            )
        }

        let reserve = max(20, maxHeartRate - restingHeartRate)
        var level = startLevel
        var points: [Point] = [Point(date: wakeTime, level: level, delta: 0)]

        for sample in hourlyHeartRate.sorted(by: { $0.date < $1.date }) where sample.date >= wakeTime {
            // Heart-rate reserve for this hour: 0 at rest, 1 at max.
            let intensity = max(0, (sample.bpm - restingHeartRate) / reserve)

            let delta: Double
            if intensity < 0.08 {
                // At or near resting while awake — genuine recovery. Charging
                // is capped low because waking rest never refills like sleep.
                delta = 2.5 * (1 - intensity / 0.08)
            } else {
                // Superlinear drain: an hour at threshold should cost far more
                // than two easy hours, or the model would reward grinding.
                delta = -(pow(intensity, 1.6) * 34)
            }

            level = min(100, max(0, level + delta))
            points.append(Point(date: sample.date, level: level, delta: delta))
        }

        let levels = points.map(\.level)
        return BodyBattery(
            points: points,
            current: Int((levels.last ?? startLevel).rounded()),
            morningPeak: Int((levels.max() ?? startLevel).rounded()),
            dayLow: Int((levels.min() ?? startLevel).rounded())
        )
    }
}

extension BodyBattery {

    var band: String {
        switch current {
        case ..<25: "Low"
        case 25..<50: "Moderate"
        case 50..<75: "Good"
        default: "High"
        }
    }

    var guidance: String {
        switch current {
        case ..<25:
            "Running on fumes. Protect tonight's sleep and keep today light."
        case 25..<50:
            "Half a tank. Fine for normal activity, not for a hard session."
        case 50..<75:
            "Good reserves. Room for real work today."
        default:
            "Full tank. Spend it."
        }
    }

    /// Net change since waking — the day's cost so far.
    var spentToday: Int { max(0, morningPeak - current) }
}
