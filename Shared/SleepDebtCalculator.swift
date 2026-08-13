import Foundation

/// The running-shortfall math behind the Sleep Debt screen, pulled out as a
/// pure function so it can be tested without a SwiftData store behind it.
///
/// Three deliberate choices:
///
/// - **Surplus does not cancel debt.** Sleeping ten hours on Saturday does
///   not undo five short weeknights; the physiology doesn't work that way and
///   a metric that says otherwise encourages exactly the wrong behaviour. Only
///   nights *below* goal contribute.
/// - **Missing nights are skipped, not counted as zero sleep.** A night you
///   didn't wear the watch isn't a night you didn't sleep, and treating it as
///   8 hours of debt would make the number useless after one forgotten charge.
/// - **Decays night-over-night rather than dropping off a hard window edge.**
///   A flat N-night cutoff makes the number lurch on a day when nothing
///   happened: the night that ages out of the window vanishes from the sum in
///   one step, so someone who slept fine last night can still see debt fall
///   sharply for a reason that has nothing to do with last night. Instead each
///   past shortfall fades out gradually every night that follows it — still a
///   "recent nights matter more than old ones" figure, just without the
///   cliff. `decayPerNight` is chosen so the total lands close to an old
///   flat-14-night sum in steady state (half-life ≈ 10 nights).
enum SleepDebtCalculator {

    static let decayPerNight = 0.933

    /// - Parameter timeAsleepMinutesNewestFirst: minutes asleep per night,
    ///   ordered most recent first. Nights the caller has already excluded
    ///   (unworn watch, etc.) simply aren't in this array.
    static func debt(timeAsleepMinutesNewestFirst nights: [Double], goalMinutes: Double) -> Double? {
        guard !nights.isEmpty else { return nil }
        return debtSeries(timeAsleepMinutesOldestFirst: nights.reversed(), goalMinutes: goalMinutes).last
    }

    /// Same as `debt(timeAsleepMinutesNewestFirst:goalMinutes:)`, but each
    /// night is judged against its own goal rather than one shared value —
    /// see `debtSeries(timeAsleepMinutesOldestFirst:goalMinutesOldestFirst:)`.
    /// - Parameter goalMinutesNewestFirst: same count and order as `nights`.
    static func debt(timeAsleepMinutesNewestFirst nights: [Double], goalMinutesNewestFirst goals: [Double]) -> Double? {
        guard !nights.isEmpty, nights.count == goals.count else { return nil }
        return debtSeries(
            timeAsleepMinutesOldestFirst: Array(nights.reversed()),
            goalMinutesOldestFirst: Array(goals.reversed())
        ).last
    }

    /// The debt figure as of *each* night, not just the final one — what a
    /// chart plotting debt over time needs.
    ///
    /// This exists because a chart is the one caller that can't just ask for
    /// "the current number": it needs a value at every point along the way,
    /// and that series has to be produced by this exact recurrence or it
    /// stops being the same metric. Before this existed, `TrendsView`'s debt
    /// chart independently reimplemented a *different* running total (a
    /// flat, non-decaying cumulative shortfall) rather than reusing this
    /// type at all — the two could and did disagree on the same nights.
    /// `debt(timeAsleepMinutesNewestFirst:goalMinutes:)` above is now just
    /// this series' last element, so the scalar and the series can never
    /// drift apart again.
    ///
    /// - Parameter timeAsleepMinutesOldestFirst: minutes asleep per night,
    ///   ordered oldest first (the reverse of `debt`'s parameter — a series
    ///   is naturally produced walking forward in time).
    /// - Returns: debt after each night, same order and count as the input.
    static func debtSeries<S: Sequence>(
        timeAsleepMinutesOldestFirst nights: S,
        goalMinutes: Double
    ) -> [Double] where S.Element == Double {
        let nights = Array(nights)
        return debtSeries(
            timeAsleepMinutesOldestFirst: nights,
            goalMinutesOldestFirst: Array(repeating: goalMinutes, count: nights.count)
        )
    }

    /// The core recurrence every other overload in this file is defined in
    /// terms of. Each night is judged against *its own* goal rather than one
    /// value applied uniformly across the whole window.
    ///
    /// This matters once a night's goal can be a *learned* figure rather
    /// than a stable, user-set one (see
    /// `SleepNightRecord.sleepNeedBaselineMinutesAtProcessing`): a learned
    /// baseline shifts as more qualifying nights accumulate, and if every
    /// past night's shortfall were recomputed against today's latest
    /// learned figure, all of history's debt numbers would quietly change
    /// every time the model updates -- flickering for reasons a user has no
    /// way to see. Each night keeps whatever goal was authoritative when it
    /// was actually processed, frozen forever after, the same way
    /// `timeZoneIdentifier` freezes a night's own recorded timezone instead
    /// of reading the device's current one.
    ///
    /// - Parameter goalMinutesOldestFirst: same count and order as `nights`.
    /// - Returns: debt after each night, same order and count as the input.
    static func debtSeries(
        timeAsleepMinutesOldestFirst nights: [Double],
        goalMinutesOldestFirst goals: [Double]
    ) -> [Double] {
        var debt = 0.0
        var series: [Double] = []
        for (minutes, goal) in zip(nights, goals) {
            debt = debt * decayPerNight + max(0, goal - minutes)
            series.append(debt)
        }
        return series
    }
}
