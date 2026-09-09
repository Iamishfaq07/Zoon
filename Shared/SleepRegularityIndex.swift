import Foundation

/// The academic Sleep Regularity Index: agreement of sleep/wake state
/// across consecutive *full 24-hour* days, rescaled to 0–100.
///
/// `SleepRegularity` is the user-facing metric. It samples a window around
/// each night (bedtime−2h to wake+2h) because Zoon has no daytime
/// activity signal, and scoring every extra daytime hour as "awake on
/// both days" would inflate and flatten every score. That reasoning is
/// still right, which is why this type does **not** replace it and is
/// not labelled "SRI" on any screen.
///
/// This exists because the textbook formula *does* walk a full calendar
/// day, including daytime awake-to-awake agreement, and because naps
/// (and split sleep) are part of that formula. A researcher, a clinician
/// export, or a future surface that wants the academic number can ask
/// for it without dragging the on-screen metric off its night-window
/// definition. Social jetlag stays on `SleepRegularity` — it is already
/// the midpoint split, and computing it twice would be two answers.
///
/// SRI = −100 + 200 × (fraction of samples that agree 24h apart). Chance
/// agreement (50%) maps to 0; perfect agreement maps to 100.
struct SleepRegularityIndex: Hashable, Sendable {
    /// 0–100. Higher is more regular.
    let index: Double
    /// Calendar days that contributed at least one comparison.
    let dayCount: Int
    /// Consecutive-day pairs that were actually compared (gaps skipped).
    let validPairCount: Int

    /// Same floor as `SleepRegularity`: a week of comparisons, not a week
    /// of nights. n days yield at most n−1 pairs.
    static let minimumDays = 7

    var hasEnoughData: Bool {
        dayCount >= Self.minimumDays && validPairCount >= Self.minimumDays - 1
    }

    /// - Parameter nights: oldest first is not required; they are sorted.
    /// - Parameter calendar: DST-aware day addition, same as `SleepRegularity`.
    static func compute(
        nights: [SleepNightFeatures],
        calendar: Calendar = .current
    ) -> SleepRegularityIndex {
        let sorted = nights.sorted { $0.bedtime < $1.bedtime }
        guard sorted.count >= 2 else {
            return SleepRegularityIndex(index: 0, dayCount: sorted.count, validPairCount: 0)
        }

        let step: TimeInterval = 300
        let day: TimeInterval = 86_400

        var agreements = 0
        var comparisons = 0
        var validPairs = 0

        // Walk consecutive nights that are actually a day apart. A gap in
        // the record (watch off for a week) must not be scored as
        // irregularity — same contract as `SleepRegularity`.
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next.bedtime.timeIntervalSince(previous.bedtime)
            guard gap > day * 0.5, gap < day * 1.5 else { continue }
            validPairs += 1

            // Full 24 hours from the earlier night's bedtime, not the
            // bedtime−2h…wake+2h window. Daytime minutes that neither
            // night covers are awake on both sides (agreement). A nap
            // recorded on only one of the two days is a disagreement —
            // that is the information this metric exists to capture.
            let windowStart = previous.bedtime
            let windowEnd = windowStart.addingTimeInterval(day)

            var cursor = windowStart
            while cursor < windowEnd {
                let asleepNow = isAsleep(sorted, at: cursor)
                let sameTimeNextDay = calendar.date(byAdding: .day, value: 1, to: cursor)
                    ?? cursor.addingTimeInterval(day)
                let asleepTomorrow = isAsleep(sorted, at: sameTimeNextDay)
                if asleepNow == asleepTomorrow { agreements += 1 }
                comparisons += 1
                cursor = cursor.addingTimeInterval(step)
            }
        }

        let index: Double
        if comparisons > 0 {
            let agreement = Double(agreements) / Double(comparisons)
            index = max(0, min(100, 2 * agreement * 100 - 100))
        } else {
            index = 0
        }

        return SleepRegularityIndex(
            index: index,
            dayCount: sorted.count,
            validPairCount: validPairs
        )
    }

    /// Asleep if *any* night in the record covers the instant. Naps and
    /// split-sleep blocks therefore count; uncovered daytime is awake.
    static func isAsleep(_ nights: [SleepNightFeatures], at instant: Date) -> Bool {
        nights.contains { $0.isAsleep(at: instant) }
    }
}
