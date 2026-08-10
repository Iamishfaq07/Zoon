import Foundation

/// Tells you whether a nap right now is a good idea, not just how long the
/// last one was — Garmin's Sleep Coach and RISE's nap guidance, reimplemented.
///
/// Deliberately conservative in one specific way: a nap that eats into
/// tonight's sleep pressure is a worse trade than staying tired for a few
/// more hours, so anything within about six hours of the planned bedtime is
/// advised against outright rather than merely discouraged.
enum NapCoach {

    struct Recommendation: Hashable {
        enum Advice: Hashable {
            case recommended(durationMinutes: Int)
            case optional
            case avoid
        }

        let advice: Advice
        let reason: String

        var isRecommended: Bool {
            if case .recommended = advice { return true }
            return false
        }
    }

    /// - Parameters:
    ///   - debtMinutes: Current estimated sleep debt (`SleepDebtState`-style),
    ///     never negative.
    ///   - plannedBedtime: Tonight's target bedtime, when known.
    ///   - napMinutesToday: Nap time already banked today.
    static func recommend(
        now: Date = .now,
        debtMinutes: Double,
        plannedBedtime: Date?,
        napMinutesToday: Double
    ) -> Recommendation {
        if napMinutesToday >= 30 {
            return Recommendation(
                advice: .avoid,
                reason: "You've already napped \(Int(napMinutesToday)) minutes today. Another nap risks cutting into tonight's sleep drive."
            )
        }

        let hoursUntilBedtime = plannedBedtime.map { $0.timeIntervalSince(now) / 3600 }

        if let hours = hoursUntilBedtime, hours < 6 {
            return Recommendation(
                advice: .avoid,
                reason: "Bedtime is under 6 hours away. A nap this close would likely reduce tonight's sleep pressure rather than add to today's."
            )
        }

        if debtMinutes < 20 {
            return Recommendation(
                advice: .optional,
                reason: "Estimated debt is minimal right now, so a nap isn't necessary -- but a short one won't cost you anything either."
            )
        }

        if debtMinutes >= 90, let hours = hoursUntilBedtime, hours >= 8 {
            return Recommendation(
                advice: .recommended(durationMinutes: 90),
                reason: "Debt is high enough, and bedtime is far enough away, that a longer ~90 minute recovery nap -- roughly one full sleep cycle -- is unlikely to interfere with tonight."
            )
        }

        let debtNote = debtMinutes >= 20
            ? " and should ease some of today's \(Int(debtMinutes)) minutes of estimated debt"
            : ""
        return Recommendation(
            advice: .recommended(durationMinutes: 20),
            reason: "A short 15-25 minute power nap now is unlikely to interfere with tonight's sleep\(debtNote)."
        )
    }
}
