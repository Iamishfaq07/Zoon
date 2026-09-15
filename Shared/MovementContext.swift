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

    /// The smallest typical step count a percentage may be stated against.
    ///
    /// A ratio needs a denominator worth dividing by. On a real device this
    /// reported "3,173 steps so far, 2566% above your typical Tuesday by this
    /// time (119)" — arithmetically correct and completely useless: 119 steps
    /// is a Tuesday the phone spent on a desk, not a typical Tuesday, and a
    /// four-digit percentage reads as an alarm rather than as context.
    ///
    /// Below this the steps are still reported; only the comparison is
    /// withheld, because the comparison is the part that has no support.
    static let minimumComparableTypical = 400

    /// Above this fraction over baseline the sentence switches from a
    /// percentage to a multiple: "about 4× your typical Tuesday" rather than
    /// "300% above". Both say the same thing; only one is readable at a
    /// glance, and past roughly this point the percentage stops being a
    /// number people convert and starts being a number they recoil from.
    static let multipleThreshold = 3.0

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
        // A denominator too small to divide by. Distinct from a zero typical
        // above: there *is* a baseline, it is simply too thin for a
        // percentage to mean anything.
        case (let steps?, let typical?, _) where typical < minimumComparableTypical:
            sentence = "\(format(steps)) steps so far. A typical \(weekdayName(weekday)) has only \(format(typical)) by this time, which is too few to compare against."
            confidence = .low
            provenance = "Today versus same weekday at this hour"
        // A real baseline that today has genuinely dwarfed. 25,000 steps
        // against a true 1,000-step Tuesday is 2400%, which is arithmetically
        // honest and still unreadable -- nobody parses a four-digit
        // percentage. A multiple is the same fact in a form that lands.
        case (let steps?, let typical?, let delta?) where delta >= multipleThreshold:
            let times = Double(steps) / Double(typical)
            sentence = "\(format(steps)) steps so far, about \(String(format: "%.0f", times))× your typical \(weekdayName(weekday)) by this time (\(format(typical)))."
            confidence = .moderate
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
