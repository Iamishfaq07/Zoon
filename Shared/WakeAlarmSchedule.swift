import Foundation

/// Date arithmetic for the one-time wake alarm, kept apart from `WakeAlarm`
/// itself so it can be tested.
///
/// `WakeAlarm` imports AlarmKit and is gated behind `#available(iOS 26.0, *)`,
/// which puts it out of reach of the standalone `ZoonTests` bundle. The part
/// worth testing is not the AlarmKit call — it's the question of *which
/// instant* to ring at, and that is pure date math.
enum WakeAlarmSchedule {

    /// How many days forward to look for a future occurrence before giving up.
    ///
    /// A week plus one. If a caller hands over a wake time so stale that
    /// rolling it forward eight times still lands in the past, something is
    /// wrong upstream and inventing an alarm is worse than declining one.
    static let maximumRollForwardDays = 8

    /// The next instant at or after `now` matching `wakeTime`'s local
    /// wall-clock time.
    ///
    /// Returns `wakeTime` untouched when it is already in the future — the
    /// normal case, since the body clock hands back an upcoming window. The
    /// roll-forward exists for the edge where the window's end has already
    /// passed today (the app opened late in the morning, say): a one-time
    /// alarm at a past instant would never fire, so tomorrow's equivalent
    /// wall-clock time is the useful answer.
    ///
    /// Steps by *calendar day*, never by a fixed 86,400 seconds. Across a DST
    /// boundary the two differ by an hour, and the intent here is "the same
    /// clock time tomorrow", which is the calendar's definition and not
    /// arithmetic's — a spring-forward night is 23 hours long, and adding
    /// 86,400 to a 07:30 wake produces 08:30.
    ///
    /// - Returns: `nil` when no future occurrence can be resolved within
    ///   ``maximumRollForwardDays``.
    static func nextFutureOccurrence(
        of wakeTime: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        if wakeTime > now { return wakeTime }

        var candidate = wakeTime
        for _ in 0..<maximumRollForwardDays {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
            if candidate > now { return candidate }
        }
        return nil
    }
}
