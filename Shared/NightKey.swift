import Foundation

/// The one place a night's stable local-date identity is built.
///
/// Zoon files a night under the calendar day you *woke up*, in the timezone the
/// night was actually recorded in — never the device's current one. That second
/// half is the load-bearing part: two `Date`s that both look like "the start of
/// some day" can disagree about *which* day the instant they wrap belongs to
/// once the device has moved, so a traveler who lands in Delhi and opens Zoon
/// would otherwise see last night's Tokyo data attach itself to the wrong day.
///
/// The format is `YYYY-MM-DD@TimeZoneIdentifier`. It is a persisted value —
/// `SleepNightRecord`, `SleepEpisodeRecord`, `JournalEntry` and
/// `BehaviorObservationRecord` all store keys in this exact shape, and backups
/// carry them too. **Do not change the format.** Anything written by an older
/// build must keep parsing, and a key that stops matching silently detaches a
/// night from its journal entry rather than failing loudly.
///
/// This existed twice before — once on `SleepSession`, once on
/// `SleepNightFeatures` — as two implementations documented as agreeing "by
/// construction". They now agree by sharing this code instead.
enum NightKey {

    /// Builds the key for the night containing `wakeInstant`, as reckoned in
    /// `timeZone`.
    ///
    /// - Parameters:
    ///   - wakeInstant: When the night ended. Passing a `startOfDay` value
    ///     already reduced in the same timezone is equivalent — only the
    ///     year/month/day components are read, so both callers land on the
    ///     same key.
    ///   - timeZone: The timezone the night was *recorded* in.
    static func make(wakeInstant: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: wakeInstant)
        return String(
            format: "%04d-%02d-%02d@%@",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            calendar.timeZone.identifier
        )
    }

    /// Convenience for the many call sites that hold a timezone *identifier*
    /// rather than a `TimeZone`, and that treat an unresolvable or
    /// pre-migration identifier as "whatever the device is on now".
    ///
    /// The fallback is deliberately lossy and deliberately loud in intent: a
    /// record written before timezones were stored genuinely does not know
    /// where it happened, and guessing the current zone is the only option
    /// that keeps it matching itself.
    static func make(wakeInstant: Date, timeZoneIdentifier: String) -> String {
        make(
            wakeInstant: wakeInstant,
            in: TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
    }
}
