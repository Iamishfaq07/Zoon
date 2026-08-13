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
        var debt = 0.0
        var series: [Double] = []
        for minutes in nights {
            debt = debt * decayPerNight + max(0, goalMinutes - minutes)
            series.append(debt)
        }
        return series
    }
}
