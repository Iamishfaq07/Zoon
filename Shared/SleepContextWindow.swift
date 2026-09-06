import Foundation

enum SleepContextWindow {
    /// Prefer a measured wake boundary. A bounded fallback also works for
    /// daytime sleepers and does not reset at midnight.
    static func waking(before bedtime: Date, previousWake: Date?) -> DateInterval {
        let fallback = bedtime.addingTimeInterval(-18 * 3600)
        let start: Date
        if let previousWake, previousWake < bedtime,
           bedtime.timeIntervalSince(previousWake) <= 36 * 3600 {
            start = previousWake
        } else { start = fallback }
        return DateInterval(start: start, end: bedtime)
    }

    static func lateCaffeine(before bedtime: Date, waking: DateInterval) -> DateInterval {
        DateInterval(start: max(waking.start, bedtime.addingTimeInterval(-8 * 3600)), end: bedtime)
    }

    /// All nap sources use the same half-open calendar day attribution.
    static func napDay(before wakeDate: Date, timeZone: TimeZone) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let wakeDay = calendar.startOfDay(for: wakeDate)
        let start = calendar.date(byAdding: .day, value: -1, to: wakeDay) ?? wakeDay.addingTimeInterval(-86_400)
        return DateInterval(start: start, end: wakeDay)
    }
}
