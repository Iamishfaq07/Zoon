import Foundation

/// Which night a behaviour belongs to, from the moment it was logged.
///
/// The one rule for every surface that files a behaviour against a night:
/// the phone Journal, Siri's Log Sleep Tag, the Coach's "log coffee", and the
/// watch's quick logs (`WatchActionEnvelope.behaviorNightDate`, which calls
/// this). They used to disagree after midnight: the watch kept a 01:00 tag on
/// the night in progress while the phone moved it to the following night.
///
/// A behaviour is about the night that follows the day it happened on, keyed
/// by the morning that night ends on. A tag at 21:00 on the 10th is about the
/// night ending on the 11th. **After midnight is the night in progress:** a
/// tag at 01:00 on the 11th is still about the night ending on the 11th,
/// because the person has not slept yet. The boundary is 04:00 by default; a
/// log at 05:30 is more often somebody already up than somebody not yet
/// asleep.
///
/// A morning feeling or a midnight awakening is about the night already
/// slept, so it does not use this.
enum BehaviorNight {

    static let defaultMorningBoundaryMinute = 4 * 60

    /// The wake-day date of the night a behaviour logged at `instant` belongs
    /// to, reckoned in `calendar` (whose time zone should be the one the log
    /// was made in). Pass the result to `NightKey.make(wakeInstant:in:)` to
    /// get the night's key.
    static func nightDate(
        forLogAt instant: Date,
        calendar: Calendar,
        morningBoundaryMinute: Int = defaultMorningBoundaryMinute
    ) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: instant)
        let minute = (components.hour ?? 12) * 60 + (components.minute ?? 0)
        if minute < morningBoundaryMinute { return instant }
        return calendar.date(byAdding: .day, value: 1, to: instant) ?? instant
    }

    /// The same, in a named time zone (the device's current one by default).
    static func nightDate(
        forLogAt instant: Date,
        timeZone: TimeZone = .current,
        morningBoundaryMinute: Int = defaultMorningBoundaryMinute
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return nightDate(forLogAt: instant, calendar: calendar, morningBoundaryMinute: morningBoundaryMinute)
    }

    /// The `NightKey` of the night a behaviour logged at `instant` belongs to.
    static func nightKey(
        forLogAt instant: Date,
        timeZone: TimeZone = .current,
        morningBoundaryMinute: Int = defaultMorningBoundaryMinute
    ) -> String {
        NightKey.make(
            wakeInstant: nightDate(forLogAt: instant, timeZone: timeZone, morningBoundaryMinute: morningBoundaryMinute),
            in: timeZone
        )
    }
}
