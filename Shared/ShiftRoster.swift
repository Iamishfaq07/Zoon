import Foundation

/// A person's work roster: repeating shifts, one-off shifts, and the dates
/// they are cancelled on.
///
/// **Why this is stored as a rule rather than as a list of dates.** A roster
/// is a pattern people describe as a pattern — "nights Monday to Thursday" —
/// and the list of dates it produces runs forever. Storing the rule keeps the
/// object small, lets a change apply to every future occurrence at once, and
/// means a roster set up in March still generates the right dates in
/// September without a migration that walks the calendar.
///
/// **Why every occurrence is resolved in the local calendar rather than
/// stored as an instant.** A shift starting at 22:00 starts at 22:00 on both
/// sides of a daylight-saving change and in both timezones somebody works
/// across; an instant does not. The clock time is what the roster means, so
/// the clock time is what is stored, and instants are produced only when a
/// concrete day is in hand.
///
/// **What this is not.** It is not a timesheet, a rota anyone else can see,
/// or a record of hours worked. Nothing here is reported anywhere, and
/// `ShiftPlan` — the thing that reads it — is explicitly schedule support and
/// not an occupational-health judgement.
struct ShiftRoster: Codable, Hashable, Sendable {

    struct Shift: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        /// Minutes from midnight on the shift's own starting day. A shift that
        /// runs past midnight is expressed as a start plus a duration, never
        /// as a start and an end that appear to run backwards.
        var startMinutes: Int
        var durationMinutes: Int
        /// `Calendar` weekday numbers this shift repeats on. Empty means the
        /// shift happens once, on `date`.
        var weekdays: Set<Int>
        /// The single day a non-repeating shift falls on, as a start-of-day.
        var date: Date?
        var label: String?

        init(
            id: UUID = UUID(),
            startMinutes: Int,
            durationMinutes: Int,
            weekdays: Set<Int> = [],
            date: Date? = nil,
            label: String? = nil
        ) {
            self.id = id
            self.startMinutes = startMinutes
            self.durationMinutes = durationMinutes
            self.weekdays = weekdays
            self.date = date
            self.label = label
        }

        var isRepeating: Bool { !weekdays.isEmpty }
    }

    /// One shift on one concrete day.
    struct Occurrence: Hashable, Sendable, Identifiable {
        let shiftID: UUID
        let start: Date
        let end: Date
        let label: String?

        var id: Date { start }
        var interval: DateInterval { DateInterval(start: start, end: end) }
        var durationMinutes: Double { end.timeIntervalSince(start) / 60 }
    }

    /// The longest shift the planner will accept. Sixteen hours is already
    /// beyond anything most rosters hold; past it the entry is far more
    /// likely to be a typo than a shift, and a typo that long would swallow
    /// every sleep window in the horizon.
    static let maximumDurationMinutes = 16 * 60

    static let minimumDurationMinutes = 30

    var shifts: [Shift] = []
    /// Days a repeating shift does not happen on, as start-of-day dates.
    /// Keyed by shift so cancelling one night off a Monday–Thursday pattern
    /// does not touch the other three.
    var skipped: [UUID: Set<Date>] = [:]

    init(shifts: [Shift] = [], skipped: [UUID: Set<Date>] = [:]) {
        self.shifts = shifts
        self.skipped = skipped
    }

    var isEmpty: Bool { shifts.isEmpty }

    /// The next `days` **local calendar days**, starting now.
    ///
    /// Not `days * 86,400` seconds. A local day is twenty-three or twenty-five
    /// hours across a clock change, so a fixed multiple of seconds runs an
    /// hour short or an hour long — and for a planner reading a roster, an
    /// hour at the far end of the window is the difference between seeing
    /// next Sunday's 22:00 night shift and not knowing it is there. The
    /// horizon is a promise about days, so it is built out of days.
    ///
    /// The seconds form survives only as a fallback for a `Calendar` that
    /// cannot add a day at all, which is not a thing any real calendar does.
    static func horizon(days: Int, from start: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: days, to: start)
            ?? start.addingTimeInterval(Double(days) * 86_400)
        return DateInterval(start: start, end: max(start, end))
    }

    /// Every occurrence whose **start** falls inside `interval`, ascending.
    ///
    /// Keyed on the start rather than on any overlap: a night shift that began
    /// yesterday and ends this morning belongs to yesterday, which is how the
    /// person who worked it thinks of it, and counting it twice would have the
    /// planner build two sleep windows around one shift.
    func occurrences(in interval: DateInterval, calendar: Calendar = .current) -> [Occurrence] {
        var results: [Occurrence] = []
        var day = calendar.startOfDay(for: interval.start)
        // One day back, because a shift starting at 23:00 on the day before
        // the interval opens can still start inside it when the interval
        // opens mid-evening.
        day = calendar.date(byAdding: .day, value: -1, to: day) ?? day

        while day <= interval.end {
            let weekday = calendar.component(.weekday, from: day)
            for shift in shifts {
                guard (Self.minimumDurationMinutes...Self.maximumDurationMinutes)
                    .contains(shift.durationMinutes) else { continue }

                let applies: Bool
                if shift.isRepeating {
                    applies = shift.weekdays.contains(weekday)
                } else if let date = shift.date {
                    applies = calendar.isDate(date, inSameDayAs: day)
                } else {
                    applies = false
                }
                guard applies else { continue }
                guard !(skipped[shift.id]?.contains(day) ?? false) else { continue }

                guard let start = calendar.date(
                    byAdding: .minute, value: shift.startMinutes, to: day
                ) else { continue }
                guard interval.contains(start) else { continue }

                let end = start.addingTimeInterval(Double(shift.durationMinutes) * 60)
                results.append(
                    Occurrence(shiftID: shift.id, start: start, end: end, label: shift.label)
                )
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return results.sorted { $0.start < $1.start }
    }

    /// The next occurrence at or after `now`, if the roster holds one inside
    /// `horizonDays`.
    func next(
        after now: Date,
        horizonDays: Int = SleepRunway.horizonDays,
        calendar: Calendar = .current
    ) -> Occurrence? {
        guard let end = calendar.date(byAdding: .day, value: horizonDays, to: now) else { return nil }
        return occurrences(in: DateInterval(start: now, end: end), calendar: calendar).first
    }
}
