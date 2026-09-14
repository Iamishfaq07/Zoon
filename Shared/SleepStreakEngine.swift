import Foundation

/// The one place a "night streak" is counted.
///
/// The previous implementation walked the nights array and stopped at the
/// first night under goal. Array adjacency is not calendar adjacency: a week
/// of Mon, Tue, Thu, Fri — with **no record at all** for Wednesday — has four
/// adjacent array elements and is not a four-night streak. A night that was
/// never recorded breaks a streak exactly as a night under goal does; the
/// claim being made is "this many nights in a row", and a missing night is
/// not one of them.
///
/// Canonical sleep-day mapping: a night is attributed to
/// `SleepNightFeatures.date`, the wake day, which is what every other engine
/// here uses. Adjacency is calendar-day adjacency in the night's own
/// timezone, so DST days (23 or 25 hours long) and travel do not create or
/// break streaks by arithmetic accident.
///
/// Goal basis: `total24hAsleepMinutes` — main sleep plus naps credited to
/// that night. This is a product decision applied in one place rather than
/// per-screen: the shortfall, the need and the debt are all computed from the
/// 24-hour total, so a day that reaches goal *with* a nap reaches goal here
/// too. Using `timeAsleepMinutes` would mean a screen could show "goal met"
/// and the streak disagree about the same night.
enum SleepStreakEngine {

    struct Result: Equatable {
        /// Nights in a row ending at the most recent recorded night.
        let current: Int
        /// The longest run anywhere in the supplied history.
        let best: Int
        /// Nights meeting goal within the trailing window, for "22 of the
        /// last 30" style copy. Not a streak: no adjacency requirement.
        let metInWindow: Int
        let windowSize: Int
    }

    /// - Parameters:
    ///   - nights: any order; sorted internally.
    ///   - goalMinutes: the night's own need where the caller has one.
    ///   - windowSize: trailing nights counted for `metInWindow`.
    static func evaluate(
        nights: [SleepNightFeatures],
        goalMinutes: Double,
        windowSize: Int = 30,
        calendar: Calendar = .current
    ) -> Result {
        let sorted = nights.sorted { $0.date < $1.date }

        // Duplicate records for one calendar day must not count twice. Keep
        // the longest, which is the one a duplicate-import scenario should
        // resolve to.
        var byDay: [Date: SleepNightFeatures] = [:]
        for night in sorted {
            var local = calendar
            local.timeZone = night.timeZone
            let key = local.startOfDay(for: night.date)
            if let existing = byDay[key], existing.total24hAsleepMinutes >= night.total24hAsleepMinutes {
                continue
            }
            byDay[key] = night
        }

        let days = byDay.keys.sorted()
        let met = Set(days.filter { day in
            (byDay[day]?.total24hAsleepMinutes ?? 0) >= goalMinutes
        })

        var current = 0
        if let last = days.last, met.contains(last) {
            var cursor = last
            while met.contains(cursor) {
                current += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                // A day with no record at all is a break, not a skip.
                guard byDay[calendar.startOfDay(for: previous)] != nil else { break }
                cursor = calendar.startOfDay(for: previous)
            }
        }

        var best = 0
        var running = 0
        var expected: Date?
        for day in days {
            let isAdjacent = expected.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
            running = (met.contains(day) && (isAdjacent || running == 0)) ? running + 1 : (met.contains(day) ? 1 : 0)
            best = max(best, running)
            expected = calendar.date(byAdding: .day, value: 1, to: day)
        }

        let window = days.suffix(windowSize)
        let metInWindow = window.filter { met.contains($0) }.count

        return Result(
            current: current,
            best: best,
            metInWindow: metInWindow,
            windowSize: min(windowSize, days.count)
        )
    }
}
