import Foundation

/// A local calendar day, as an identity rather than as an instant.
///
/// **Why an instant is the wrong identity.** "The day I woke up on" is a
/// civil date — the 3rd — not a moment. Representing it as `startOfDay` makes
/// it a moment, and a moment is only meaningful with the timezone that
/// produced it: local midnight in Delhi and local midnight in London on the
/// same date are five and a half hours apart. `SleepStreakEngine` stored day
/// identities computed in each night's *own* timezone and then looked them up
/// with the *device's current* calendar, so the day after flying home, every
/// stored key missed its lookup and a genuine streak broke for no reason a
/// user could see.
///
/// Comparing civil dates instead removes the whole class of problem. There is
/// nothing to get wrong across travel, and nothing to get wrong across DST
/// either: a 23- or 25-hour day still has exactly one date.
///
/// **What this deliberately does not carry** is the timezone. `NightKey`
/// does, and correctly — it identifies *a specific night's record*, which has
/// to keep matching its own journal entry after the sleeper moves. This is a
/// different question: whether two nights fall on consecutive days. Two
/// consecutive nights recorded either side of a flight are still consecutive,
/// and a key that included the zone would say otherwise.
struct SleepDayKey: Hashable, Comparable, Sendable, CustomStringConvertible {

    let year: Int
    let month: Int
    let day: Int

    /// The day `date` falls on, as reckoned where it was recorded.
    init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    private init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Civil-date arithmetic, done in UTC.
    ///
    /// UTC has no daylight saving, so "the day before" is unambiguous and
    /// cannot land on a repeated or missing local hour. The result is a date,
    /// not a time, so the zone the arithmetic ran in never escapes.
    private static let arithmeticCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private var noonUTC: Date? {
        Self.arithmeticCalendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )
    }

    func advanced(by days: Int) -> SleepDayKey {
        guard let noonUTC,
              let moved = Self.arithmeticCalendar.date(byAdding: .day, value: days, to: noonUTC)
        else { return self }
        let components = Self.arithmeticCalendar.dateComponents([.year, .month, .day], from: moved)
        return SleepDayKey(
            year: components.year ?? year,
            month: components.month ?? month,
            day: components.day ?? day
        )
    }

    var previous: SleepDayKey { advanced(by: -1) }
    var next: SleepDayKey { advanced(by: 1) }

    func isDayAfter(_ other: SleepDayKey) -> Bool { other.next == self }

    static func < (lhs: SleepDayKey, rhs: SleepDayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

extension SleepNightFeatures {

    /// The local day this night is filed under — the day it was woken on, in
    /// the timezone it was recorded in.
    var sleepDayKey: SleepDayKey { SleepDayKey(date, timeZone: timeZone) }
}
