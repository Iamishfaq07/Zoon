import Foundation

/// Which night a Snore Check session belongs to.
///
/// Decided from when the session *started*, with the same rule a logged
/// behaviour uses (`BehaviorNight`): a start in the evening is the night that
/// ends the next morning, a start after midnight (before 04:00) the night that
/// ends that morning. The stop instant is not a safe identity -- a session
/// stopped at 23:50 would land on the night before -- and neither is the
/// moment a crashed session last checkpointed. Both used to be used, and a
/// recovered partial session merged into the previous night's summary.
enum SnoreNight {

    /// The wake-day date of the night a session started at `start` belongs
    /// to, reckoned in `timeZone` (the one the session was recorded in).
    static func date(forSessionStartedAt start: Date, in timeZone: TimeZone) -> Date {
        BehaviorNight.nightDate(forLogAt: start, timeZone: timeZone)
    }

    /// The `NightKey` of that night.
    static func key(forSessionStartedAt start: Date, in timeZone: TimeZone) -> String {
        NightKey.make(wakeInstant: date(forSessionStartedAt: start, in: timeZone), in: timeZone)
    }
}
