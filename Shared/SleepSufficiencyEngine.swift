import Foundation

/// The single answer to "did this person get enough sleep?".
///
/// Zoon has five numbers that all sound like they answer that question and do
/// not: main-sleep duration, total 24-hour sleep, the user's chosen goal, the
/// estimated personal need, and the resulting debt. Before this existed each
/// screen picked its own pair, which is how the same night could read as
/// sufficient in one place and short in another.
///
/// Two rules, and they are the whole type:
///
/// 1. **Sufficiency is measured against total 24-hour sleep, not main sleep.**
///    A 45-minute nap is real sleep. Excluding it reports a deficit the person
///    does not have.
/// 2. **The comparison basis is never implicit.** `Basis` is required, and it
///    is carried on the result, because "you met your goal" and "you met your
///    estimated need" are different claims and only one of them is the user's
///    own decision.
enum SleepSufficiencyEngine {

    /// What a sufficiency figure was measured against.
    ///
    /// This is not cosmetic. A goal is a target the user deliberately chose;
    /// a need is Zoon's estimate about their body. Presenting a goal streak
    /// as evidence about someone's physiology overstates what Zoon knows,
    /// and presenting an estimate as a goal implies they picked it.
    enum Basis: String, Codable, Sendable {
        /// Zoon's per-night estimate of how much this person needs.
        case personalNeed
        /// The target the user set in Settings.
        case userGoal

        /// How to describe this basis in user-facing copy. Deliberately
        /// plain: "goal" must read as a choice, "estimated need" must read
        /// as an estimate.
        var label: String {
            switch self {
            case .personalNeed: "estimated need"
            case .userGoal: "goal"
            }
        }
    }

    struct Result: Sendable, Equatable {
        /// 0...100. Capped at 100 — sleeping well past the target is not a
        /// deficiency in the other direction; this measure simply has
        /// nothing further to say once the target is met.
        let percent: Double
        /// Minutes actually slept across the whole 24 hours.
        let sleptMinutes: Double
        /// What `percent` was measured against.
        let targetMinutes: Double
        let basis: Basis

        var isMet: Bool { percent >= 100 }

        /// Shortfall in minutes, or zero once the target is met.
        var shortfallMinutes: Double { max(0, targetMinutes - sleptMinutes) }
    }

    /// Sufficiency for one night.
    ///
    /// - Parameters:
    ///   - total24hAsleepMinutes: Main sleep **plus** naps. Passing main
    ///     sleep alone is the mistake this type exists to prevent.
    ///   - target: The night's personal need, or the user's goal.
    ///   - basis: Which of those `target` is. Required on purpose.
    static func evaluate(
        total24hAsleepMinutes: Double,
        target: Double,
        basis: Basis
    ) -> Result {
        let safeTarget = max(target, 1)
        return Result(
            percent: min(100, total24hAsleepMinutes / safeTarget * 100),
            sleptMinutes: total24hAsleepMinutes,
            targetMinutes: target,
            basis: basis
        )
    }

    /// Sufficiency for one night against its own recorded need.
    ///
    /// Falls back to `goalMinutes` when a night predates learned need — and
    /// says so via the returned `basis`, rather than quietly reporting a
    /// goal comparison as a need comparison.
    static func evaluate(
        night: SleepNightFeatures,
        goalMinutes: Double
    ) -> Result {
        if let need = night.sleepNeedBaselineMinutes {
            return evaluate(
                total24hAsleepMinutes: night.total24hAsleepMinutes,
                target: need,
                basis: .personalNeed
            )
        }
        return evaluate(
            total24hAsleepMinutes: night.total24hAsleepMinutes,
            target: goalMinutes,
            basis: .userGoal
        )
    }

    /// Mean sufficiency across a window, each night measured against its
    /// **own** recorded need rather than one current setting applied
    /// retroactively — the same per-night semantics canonical Sleep Debt
    /// uses. Applying today's target to a year of history silently rescores
    /// every night under a baseline that was never in effect.
    ///
    /// Returns `nil` for an empty window rather than a misleading zero.
    static func averagePercent(
        nights: [SleepNightFeatures],
        goalMinutes: Double
    ) -> Double? {
        guard !nights.isEmpty else { return nil }
        let values = nights.map { evaluate(night: $0, goalMinutes: goalMinutes).percent }
        return Statistics.mean(values)
    }

    /// Whether a night met a target the user deliberately chose.
    ///
    /// Separate from `evaluate(night:goalMinutes:)` because a goal streak is
    /// a different claim: it is about a commitment being kept, not about
    /// whether the person's body got what it needed. Callers rendering
    /// streaks and badges should use this and say "goal".
    static func meetsGoal(
        night: SleepNightFeatures,
        goalMinutes: Double
    ) -> Bool {
        evaluate(
            total24hAsleepMinutes: night.total24hAsleepMinutes,
            target: goalMinutes,
            basis: .userGoal
        ).isMet
    }
}
