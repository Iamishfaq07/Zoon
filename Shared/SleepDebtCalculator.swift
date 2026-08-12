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
        // Walk oldest-to-newest so the decay compounds forward in time,
        // ending on the most recent night.
        var debt = 0.0
        for minutes in nights.reversed() {
            debt = debt * decayPerNight + max(0, goalMinutes - minutes)
        }
        return debt
    }
}
