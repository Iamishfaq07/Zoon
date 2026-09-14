import Foundation

/// Turns "minutes from midnight" into the actual instant that bedtime falls on.
///
/// Plans store a bedtime as minutes from midnight, wrapping past 1440 for an
/// after-midnight target: 23:10 is tonight, 00:40 is tomorrow. Resolving that
/// needs two things the obvious arithmetic gets wrong.
///
/// **A day is not always 86,400 seconds.** Adding `minutes * 60` to midnight
/// assumes every hour between exists. On a spring-forward day one does not, so
/// midnight plus 23h10m of elapsed seconds lands at 00:10 the following day —
/// an hour past the bedtime it was meant to name. The same applies to rolling
/// an after-midnight target forward: `+86_400` is a day only on the 363 days
/// that have 24 hours. Calendar arithmetic asks for a wall-clock time and gets
/// the instant that wall clock actually happens at.
///
/// **An after-midnight bedtime is in the past.** Resolved against today's
/// midnight alone, 00:40 has already gone by the time anyone is deciding about
/// it, which made every evening nap look safe to a coach comparing "how long
/// until bed".
///
/// Extracted from `TodayView` so the DST cases can be tested; a private helper
/// inside a `View` cannot be.
enum PlannedBedtimeResolver {

    /// The next instant at which the plan's target bedtime occurs.
    ///
    /// - Parameters:
    ///   - minutesFromMidnight: may exceed 1440 or be negative; it is wrapped.
    ///   - now: the moment to find the next occurrence after.
    /// - Returns: `nil` only when the calendar cannot form the date at all.
    static func nextOccurrence(
        ofMinutesFromMidnight minutesFromMidnight: Double,
        after now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let wrapped = (minutesFromMidnight.rounded().truncatingRemainder(dividingBy: 1440) + 1440)
            .truncatingRemainder(dividingBy: 1440)
        let hour = Int(wrapped) / 60
        let minute = Int(wrapped) % 60

        guard let today = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: now
        ) else { return nil }

        if today > now { return today }
        // Tomorrow's *same wall-clock time*, which on a DST boundary is not
        // 24 hours away.
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
    }
}
