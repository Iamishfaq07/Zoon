import Foundation

/// The nights a claim rests on, as one readable list.
///
/// Used wherever a result says "which nights counted" -- an experiment's
/// before and during sides, a correlation's tagged nights -- so the same
/// night reads the same way on every screen.
enum EvidenceNights {
    /// "Mon, Sep 14 · Tue, Sep 15", sorted and de-duplicated by day, or
    /// "none" for an empty list. Joined with " · " rather than a comma:
    /// several locales already put a comma inside one date, and
    /// "Mon, Sep 14, Tue, Sep 15" does not say where one night ends.
    static func list(_ dates: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        guard !days.isEmpty else { return "none" }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return days.map { $0.formatted(style) }.joined(separator: " · ")
    }
}
