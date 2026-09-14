import Foundation

/// Steps and active energy as context, never as a score input.
///
/// Missing is not zero: a nil step count is "not recorded", not a sedentary
/// day. The sentence compares *so far today* against *this weekday by this
/// time*, so a Monday morning is not judged against a Saturday afternoon.
enum MovementContext {

    struct Snapshot: Hashable, Sendable {
        let stepsSoFar: Int?
        let typicalStepsByNow: Int?
        let percentVsTypical: Double?
        let activeEnergyKcal: Double?
        let weekday: Int
        let sentence: String
        let confidence: MetricConfidence
        let provenance: String
    }

    /// - Parameters:
    ///   - stepsSoFar: HealthKit step count today, or `nil` if unauthorized
    ///     or not recorded. Never pass 0 to mean "unknown".
    ///   - typicalStepsByNow: median steps for this weekday at this hour
    ///     across prior weeks. `nil` until enough matching hours exist.
    static func snapshot(
        stepsSoFar: Int?,
        typicalStepsByNow: Int?,
        activeEnergyKcal: Double? = nil,
        weekday: Int,
        now: Date = .now
    ) -> Snapshot {
        let percent: Double?
        if let steps = stepsSoFar, let typical = typicalStepsByNow, typical > 0 {
            percent = (Double(steps) - Double(typical)) / Double(typical)
        } else {
            percent = nil
        }

        let sentence: String
        let confidence: MetricConfidence
        let provenance: String

        switch (stepsSoFar, typicalStepsByNow, percent) {
        case (nil, _, _):
            sentence = "Steps for today have not been recorded, so movement is unknown rather than low."
            confidence = .insufficient
            provenance = "Missing HealthKit step count"
        case (let steps?, nil, _):
            sentence = "\(format(steps)) steps so far. There is not yet a typical \(weekdayName(weekday)) by this time to compare with."
            confidence = .low
            provenance = "Today's steps only"
        // A typical of zero is a real observation -- a weekday this person
        // genuinely has not moved by this hour in the past -- but it makes
        // the percentage undefined, so `percent` is nil and the tuple fell
        // through to `default`, reporting *recorded* steps as unknown.
        // Missing is not zero was the principle; this was its mirror image,
        // zero treated as missing.
        case (let steps?, let typical?, nil) where typical == 0:
            sentence = steps == 0
                ? "No steps yet, and no steps by this time on a typical \(weekdayName(weekday)) either."
                : "\(format(steps)) steps so far. A typical \(weekdayName(weekday)) has none by this time, so there is no percentage to compare."
            confidence = .low
            provenance = "Today versus same weekday at this hour"
        case (let steps?, let typical?, let delta?):
            let absPct = Int((abs(delta) * 100).rounded())
            if abs(delta) < 0.08 {
                sentence = "\(format(steps)) steps so far — close to your usual \(weekdayName(weekday)) by this time (\(format(typical)))."
                confidence = .moderate
            } else if delta < 0 {
                sentence = "\(format(steps)) steps so far, \(absPct)% below your typical \(weekdayName(weekday)) by this time (\(format(typical)))."
                confidence = .moderate
            } else {
                sentence = "\(format(steps)) steps so far, \(absPct)% above your typical \(weekdayName(weekday)) by this time (\(format(typical)))."
                confidence = .moderate
            }
            provenance = "Today versus same weekday at this hour"
        default:
            sentence = "Movement is unknown."
            confidence = .insufficient
            provenance = "Missing"
        }

        _ = now
        _ = activeEnergyKcal
        return Snapshot(
            stepsSoFar: stepsSoFar,
            typicalStepsByNow: typicalStepsByNow,
            percentVsTypical: percent,
            activeEnergyKcal: activeEnergyKcal,
            weekday: weekday,
            sentence: sentence,
            confidence: confidence,
            provenance: provenance
        )
    }

    private static func format(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }
}
