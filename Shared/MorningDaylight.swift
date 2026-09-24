import Foundation

/// Morning daylight, measured rather than asked.
///
/// Apple Watch records time in daylight (`HKQuantityType(.timeInDaylight)`),
/// and the journal has always asked "Did you spend time outdoors this
/// morning?" by hand. When Lifestyle Insights is on and the watch measured
/// enough daylight in the morning window, the answer for tonight is filled
/// in as *yes*, marked as coming from Health.
///
/// Never *no*: no measured daylight means the watch was not worn, was under
/// a sleeve, or the type was never authorised as easily as it means the
/// person stayed in. Only a person can say no (`BehaviorObservationSource`),
/// and an answer they already gave is never replaced.
enum MorningDaylight {

    /// Enough to count as "time outdoors this morning". Ten minutes is the
    /// low end of what circadian guidance treats as a meaningful morning dose.
    static let minimumMinutes: Double = 10

    /// 05:00 to 11:00 local time.
    static let windowStartHour = 5
    static let windowEndHour = 11

    /// The morning window on `day`, or the part of it that has happened by
    /// `now`. `nil` before it opens.
    static func window(on day: Date, now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let start = calendar.startOfDay(for: day)
        guard let open = calendar.date(byAdding: .hour, value: windowStartHour, to: start),
              let close = calendar.date(byAdding: .hour, value: windowEndHour, to: start) else { return nil }
        let end = min(close, now)
        guard end > open else { return nil }
        return DateInterval(start: open, end: end)
    }

    /// Whether a measured amount answers the question with yes. `nil` (not
    /// measured) and anything short of the minimum answer nothing.
    static func counts(_ minutes: Double?) -> Bool {
        guard let minutes, minutes.isFinite else { return false }
        return minutes >= minimumMinutes
    }

    /// A morning's daylight bears on the night that follows it, which the
    /// journal files under the next morning's date.
    static func nightDate(for day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }
}
