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
                reason: "Based on your schedule, another nap is more likely to cut into tonight's sleep drive."
            )
        }

        let hoursUntilBedtime = plannedBedtime.map { $0.timeIntervalSince(now) / 3600 }

        if let hours = hoursUntilBedtime, hours < 6 {
            return Recommendation(
                advice: .avoid,
                reason: "Bedtime is under 6 hours away. A nap this close is more likely to reduce tonight's sleep pressure than add to today."
            )
        }

        if debtMinutes < 20 {
            return Recommendation(
                advice: .optional,
                reason: "Estimated debt is minimal right now, so a nap isn't necessary — a short one is less likely to shift tonight."
            )
        }

        if debtMinutes >= 90, let hours = hoursUntilBedtime, hours >= 8 {
            return Recommendation(
                advice: .recommended(durationMinutes: 90),
                reason: "Debt is high enough, and bedtime is far enough away, that a longer ~90 minute nap may allow more complete sleep-stage progression, though cycle length varies. Based on your schedule, it is less likely to interfere with tonight."
            )
        }

        let debtNote = debtMinutes >= 20
            ? " and may ease some of today's \(Int(debtMinutes)) minutes of estimated debt"
            : ""
        return Recommendation(
            advice: .recommended(durationMinutes: 20),
            reason: "Based on your schedule, a short 15–25 minute nap now is less likely to interfere with tonight's sleep\(debtNote)."
        )
    }
}
