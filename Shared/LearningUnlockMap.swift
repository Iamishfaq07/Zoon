import Foundation

/// What Zoon can tell you after how many nights (audit §17.5).
///
/// Every threshold is read from the engine that enforces it, not restated, so
/// this map cannot promise something at seven nights that the code withholds
/// until fourteen. It counts nights, never dates: a night missed is a night
/// still needed, and a date would be a guess about when you will wear the
/// watch.
enum LearningUnlockMap {

    struct Milestone: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        /// What becomes available, in one sentence.
        let detail: String
        let requiredNights: Int
    }

    enum State: Equatable, Sendable {
        case unlocked
        /// The next milestone, with how many more nights it needs.
        case next(remaining: Int)
        case later(remaining: Int)
    }

    /// In the order they unlock.
    static let milestones: [Milestone] = [
        Milestone(
            id: "stagePattern",
            title: "Your own stage pattern",
            detail: "Sleep Intelligence compares tonight's deep and REM share with your recent nights from the same watch.",
            requiredNights: SleepIntelligenceScore.minimumStageBaselineNights
        ),
        Milestone(
            id: "regularity",
            title: "Regularity",
            detail: "A regularity index needs a week of night-to-night comparisons.",
            requiredNights: SleepRegularity.minimumNights
        ),
        Milestone(
            id: "sleepHealth",
            title: "Sleep Health",
            detail: "The multi-part Sleep Health summary is reported once a week of nights is in the window.",
            requiredNights: SleepHealth.minimumNights
        ),
        Milestone(
            id: "personalWASO",
            title: "Your own disturbed-night line",
            detail: "Recovery planning judges a broken night against your usual wake time after sleep onset instead of a fixed floor.",
            requiredNights: RecoveryDayPlan.minimumHistoryNights
        ),
        Milestone(
            id: "bodyClock",
            title: "Body clock",
            detail: "Your sleep window stops being an estimate once weekday and weekend patterns have each been seen twice.",
            requiredNights: BodyClock.minimumNights
        ),
        Milestone(
            id: "forecasts",
            title: "Ranges, not guesses",
            detail: "Forecasts come with an honest range read from your own nights.",
            requiredNights: UncertaintyForecast.minimumNights
        ),
        Milestone(
            id: "playbook",
            title: "Sleep Playbook",
            detail: "What tends to go with your better and worse nights, once there is enough history to separate them.",
            requiredNights: SleepPlaybook.minimumNights
        )
    ].sorted { $0.requiredNights < $1.requiredNights }

    /// Each milestone's state for someone with `nightCount` nights. Only the
    /// first locked milestone is `next`; ties at the same threshold share it.
    static func progress(nightCount: Int) -> [(milestone: Milestone, state: State)] {
        let nights = max(0, nightCount)
        let nextThreshold = milestones.first { $0.requiredNights > nights }?.requiredNights
        return milestones.map { milestone in
            let remaining = milestone.requiredNights - nights
            if remaining <= 0 { return (milestone, .unlocked) }
            if milestone.requiredNights == nextThreshold { return (milestone, .next(remaining: remaining)) }
            return (milestone, .later(remaining: remaining))
        }
    }

    /// "3 more nights", "1 more night".
    static func remainingCopy(_ remaining: Int) -> String {
        remaining == 1 ? "1 more night" : "\(remaining) more nights"
    }
}
