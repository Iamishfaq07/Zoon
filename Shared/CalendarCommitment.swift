import Foundation

/// The smallest calendar fact Zoon is allowed to keep: a start time.
///
/// Titles, attendees, locations and notes are not stored. The default use
/// is "tomorrow's first meaningful commitment starts at 8:30 AM." An all-day
/// event is not a start time and is dropped by `firstMeaningful(in:after:)`.
struct CalendarCommitment: Hashable, Sendable {
    enum Source: String, Sendable { case manual, calendar }
    let start: Date
    let durationMinutes: Double?
    let isAllDay: Bool
    let source: Source

    var asTomorrowEvent: ZoonTomorrow.Event {
        ZoonTomorrow.Event(start: start, isAllDay: isAllDay, source: source == .calendar ? .calendar : .manual)
    }
}

enum CalendarCommitmentPicker {

    /// Earliest non-all-day event tomorrow whose start is before 14:00.
    ///
    /// Duplicates at the same instant collapse to one. Events already in the
    /// past relative to `now` are skipped so a late-evening check still
    /// finds *tomorrow* rather than a leftover from this morning.
    static func firstMeaningful(
        in events: [CalendarCommitment],
        after now: Date,
        calendar: Calendar = .current
    ) -> CalendarCommitment? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        let start = calendar.startOfDay(for: tomorrow)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        let unique = Dictionary(grouping: events, by: \.start).compactMap(\.value.first)
        return unique
            .filter { event in
                guard !event.isAllDay else { return false }
                guard event.start >= start, event.start < end else { return false }
                return calendar.component(.hour, from: event.start) < ZoonTomorrow.latestMorningEventHour
            }
            .sorted { $0.start < $1.start }
            .first
    }
}
