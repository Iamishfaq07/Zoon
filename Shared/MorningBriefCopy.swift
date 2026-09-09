import Foundation

/// Lock-screen copy for the morning brief notification.
///
/// `BedtimeReminder` refuses to put health numbers on a lock screen — anyone
/// in the room can read it, and "you slept 4h12m" is not something to
/// broadcast to a bedroom. The brief itself is full of numbers. This is the
/// strip that keeps the notification on the right side of that line.
enum MorningBriefCopy {

    static let title = "Morning brief"

    /// Fallback when the tip itself would leak a measurement.
    static let genericBody = "Open Zoon for the three-line version of last night. Numbers stay off the lock screen."

    /// - Parameter actionableTip: `SleepInsight.actionableTip` for last night.
    ///   Advice, not a score — but the rules still name durations when the
    ///   action is "make up 90 minutes", so this has to inspect the string
    ///   rather than trust the field name.
    static func body(actionableTip: String) -> String {
        let trimmed = actionableTip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return genericBody }
        return containsMeasurement(trimmed) ? genericBody : trimmed
    }

    /// Durations, clock times, percents, bpm. A tip that names any of these
    /// is a measurement wearing an imperative.
    static func containsMeasurement(_ text: String) -> Bool {
        let patterns = [
            #"\d+\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b"#,
            #"\b\d{1,2}:\d{2}\b"#,
            #"\b\d+\s*%"#,
            #"\b\d+\s*(bpm|ms)\b"#,
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}
