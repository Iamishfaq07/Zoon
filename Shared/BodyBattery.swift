import Foundation

/// A 0–100 energy reserve that charges while you rest and drains as you spend.
///
/// Zoon's explainable energy-reserve model. It is a wellness visualization,
/// not a physiological measurement or an implementation of another product's
/// proprietary score. Where recovery is a morning summary, this is a running
/// accounting curve whose input provenance stays visible.
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

    enum RestingBaselineSource: String, Codable, Hashable, Sendable {
        case personalBaseline
        case nightlyRestingHeartRate
        case sleepingLowEstimate
        case unavailable

        var isPersonalized: Bool { self == .personalBaseline }
    }

    /// Hourly samples across the day, oldest first.
    let points: [Point]
    /// Level right now (or at the last sample).
    let current: Int
    /// Level at wake — what the night bought you.
    let morningPeak: Int
    /// Lowest point reached today.
    let dayLow: Int
    /// Provenance for the threshold driving daytime drain. A precise-looking
    /// curve must disclose when it lacks a stable personal resting baseline.
    var restingBaselineSource: RestingBaselineSource = .unavailable

    /// What the overnight charge — the level the whole day is drawn down
    /// from — was actually built on.
    ///
    /// Energy consumed `recovery.percent` as a bare number. Recovery has had
    /// a real confidence for a while and the UI now refuses to *state* a
    /// score below `.insufficient`, but the number still flowed into here
    /// unchanged: a 92 computed from sleep duration alone charged the battery
    /// exactly as a 92 built on HRV, resting heart rate and respiration did.
    /// The user then saw a precise Energy figure resting on a Recovery figure
    /// Zoon had already declined to show them.
    enum Provenance: String, Codable, Hashable, Sendable {
        /// Recovery was statable and well covered.
        case fullPhysiologicalRecovery
        /// Recovery was statable but on partial physiology.
        case partialRecovery
        /// Recovery could not be stated; the charge is a sleep-derived
        /// estimate and must be labelled as one.
        case sleepDerivedEstimate
        /// Not enough to model a day at all.
        case insufficient

        var label: String {
            switch self {
            case .fullPhysiologicalRecovery: "Full physiological recovery input"
            case .partialRecovery: "Partial recovery input"
            case .sleepDerivedEstimate: "Sleep-derived estimate"
            case .insufficient: "Insufficient data"
            }
        }

        /// Whether a precise number may be presented.
        var isPresentable: Bool { self != .insufficient }
    }

    var provenance: Provenance = .insufficient

    /// Energy can never be more trustworthy than the recovery it was charged
    /// from, and is further limited by whether the drawdown had a
    /// personalised resting rate to work against. The weaker of the two,
    /// never their average — the same rule Recovery itself uses.
    var confidence: MetricConfidence {
        let fromProvenance: MetricConfidence = switch provenance {
        case .fullPhysiologicalRecovery: .high
        case .partialRecovery: .moderate
        case .sleepDerivedEstimate: .low
        case .insufficient: .insufficient
        }
        let fromResting: MetricConfidence = restingBaselineSource.isPersonalized
            ? .high
            : (restingBaselineSource == .unavailable ? .low : .moderate)
        return min(fromProvenance, fromResting)
    }

    struct Point: Codable, Hashable, Sendable, Identifiable {
        let date: Date
        let level: Double
        /// Net change over this hour. Negative = drain.
        let delta: Double
        var id: Date { date }
        var isCharging: Bool { delta > 0 }
    }

    static let empty = BodyBattery(points: [], current: 0, morningPeak: 0, dayLow: 0)

    var isEstimate: Bool { !restingBaselineSource.isPersonalized }

    // MARK: - Build

    /// Charge banked overnight, 0–100.
    ///
    /// Recovery quality dominates: eight hours of fragmented sleep after a hard
    /// day genuinely does not refill the tank, and a model that paid out purely
    /// on hours in bed would say it did.
    /// - Parameter recoveryPercent: `nil` when Recovery cannot be stated.
    ///   The charge then falls back to sleep alone rather than consuming a
    ///   number the rest of the app is refusing to show, and the caller
    ///   records `.sleepDerivedEstimate` so every surface can say so.
    static func overnightCharge(
        recoveryPercent: Int?,
        sleepPerformance: Double
    ) -> Double {
        let sleep = min(1, sleepPerformance / 100)
        // 25 floor so a terrible night still leaves something to spend —
        // a zero would be both wrong and useless.
        guard let recoveryPercent else {
            // Sleep carries the whole charge rather than being blended with
            // an unstatable recovery figure. Deliberately not "assume
            // average recovery": that is the fabrication this avoids.
            return 25 + sleep * 75
        }
        let recovery = Double(recoveryPercent) / 100
        return 25 + (recovery * 0.6 + sleep * 0.4) * 75
    }

    /// Maps Recovery's own presentation decision onto Energy's provenance,
    /// so the two cannot disagree about whether the day is measured.
    static func provenance(
        for recovery: RecoveryPresentationState
    ) -> Provenance {
        switch recovery {
        case .available(_, let confidence):
            confidence >= .moderate ? .fullPhysiologicalRecovery : .partialRecovery
        case .limited:
            .sleepDerivedEstimate
        case .buildingBaseline:
            .sleepDerivedEstimate
        case .unavailable:
            .insufficient
        }
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
        maxHeartRate: Double,
        restingBaselineSource: RestingBaselineSource = .personalBaseline
    ) -> BodyBattery {

        guard !hourlyHeartRate.isEmpty else {
            let level = Int(startLevel.rounded())
            var result = BodyBattery(
                points: [Point(date: wakeTime, level: startLevel, delta: 0)],
                current: level,
                morningPeak: level,
                dayLow: level
            )
            result.restingBaselineSource = restingBaselineSource
            return result
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
        var result = BodyBattery(
            points: points,
            current: Int((levels.last ?? startLevel).rounded()),
            morningPeak: Int((levels.max() ?? startLevel).rounded()),
            dayLow: Int((levels.min() ?? startLevel).rounded())
        )
        result.restingBaselineSource = restingBaselineSource
        return result
    }

    /// Honest fallback when no defensible resting threshold exists. It shows
    /// only what the night contributed and refuses to model daytime drain.
    static func overnightOnly(startLevel: Double, wakeTime: Date) -> BodyBattery {
        let level = Int(startLevel.rounded())
        return BodyBattery(
            points: [Point(date: wakeTime, level: startLevel, delta: 0)],
            current: level,
            morningPeak: level,
            dayLow: level,
            restingBaselineSource: .unavailable
        )
    }

    /// One line naming the weakest thing this curve rests on.
    ///
    /// Energy has two independent weaknesses and this used to report only the
    /// second. The *charge* sets the level the day starts from, and comes
    /// from Recovery -- so an Energy figure built from sleep alone, with no
    /// recovery score behind it, showed no caveat at all as long as the
    /// resting baseline happened to be personal. The *drawdown* needs a
    /// resting rate to measure effort against.
    ///
    /// The charge is named first when both are weak: it sets the number the
    /// whole day is subtracted from, so a wrong starting level is wrong all
    /// day, while a rough drawdown only drifts.
    var confidenceNote: String? {
        let fromCharge: String? = switch provenance {
        case .fullPhysiologicalRecovery: nil
        case .partialRecovery: "Charged from a partial recovery score, so this morning's level is approximate."
        case .sleepDerivedEstimate: "Charged from sleep alone — no recovery score was available for last night."
        case .insufficient: "Not enough of last night to charge this reliably."
        }
        let fromDrawdown: String? = switch restingBaselineSource {
        case .personalBaseline: nil
        case .nightlyRestingHeartRate: "Estimated from last night's resting heart rate while your personal baseline builds."
        case .sleepingLowEstimate: "Estimated from the night's lowest heart-rate reading; daytime drain may be less reliable."
        case .unavailable: "Overnight reserve only. Daytime change needs a personal resting heart-rate baseline."
        }
        return fromCharge ?? fromDrawdown
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
