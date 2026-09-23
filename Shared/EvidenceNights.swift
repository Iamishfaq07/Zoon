import Foundation

/// The nights a claim rests on, as one readable list.
///
/// Used wherever a result says "which nights counted" -- an experiment's
/// before and during sides, a correlation's tagged nights -- so the same
/// night reads the same way on every screen.
enum EvidenceNights {
    /// "Mon 14 Sep, Tue 15 Sep", sorted and de-duplicated by day, or
    /// "none" for an empty list.
    static func list(_ dates: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        guard !days.isEmpty else { return "none" }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return days.map { $0.formatted(style) }.joined(separator: ", ")
    }
}
