import Foundation

/// The morning a "tomorrow" plan is actually about.
///
/// Calendar arithmetic says tomorrow is `now + 1 day`. At 1 AM that is the
/// wrong answer: the person has not slept yet, and the commitment they are
/// arranging tonight around is the one eight hours away, not thirty-two.
/// Every commitment path — the EventKit predicate, the picker, the manual
/// time, the stored-record expiry check — has to agree on which day that is,
/// or a commitment gets written under one definition and read back under
/// another, which is how a stale time survives into a day it does not belong
/// to.
enum PlanningDay {

    /// Before this hour, the morning being planned for is still today's.
    ///
    /// Four is where the app already draws the night boundary elsewhere (see
    /// `SleepDayKey`), and a commitment at 03:30 is night work rather than a
    /// morning start in any case.
    static let lateNightCutoffHour = 4

    /// The local day whose morning the plan is for, as a half-open interval.
    static func morning(after now: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let start: Date
        if calendar.component(.hour, from: now) < lateNightCutoffHour {
            start = today
        } else {
            guard let next = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            start = next
        }
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }
}

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
    /// EventKit's identifier for the event, when it came from EventKit.
    ///
    /// Kept so a stored record can be recognised as the *same* commitment
    /// across reads rather than merely one that happens to start at the same
    /// minute. It is an opaque identifier, not content: no title travels
    /// with it.
    var eventIdentifier: String? = nil

    var asTomorrowEvent: ZoonTomorrow.Event {
        ZoonTomorrow.Event(start: start, isAllDay: isAllDay, source: source == .calendar ? .calendar : .manual)
    }
}

enum CalendarCommitmentPicker {

    /// Earliest non-all-day event on the morning being planned for, whose
    /// start is before 14:00.
    ///
    /// Duplicates at the same instant collapse to one. The day is
    /// `PlanningDay.morning(after:)` rather than a raw `now + 1 day`, so a
    /// late-evening check finds the coming morning and a 1 AM check does not
    /// skip past it.
    static func firstMeaningful(
        in events: [CalendarCommitment],
        after now: Date,
        calendar: Calendar = .current
    ) -> CalendarCommitment? {
        guard let window = PlanningDay.morning(after: now, calendar: calendar) else { return nil }

        let unique = Dictionary(grouping: events, by: \.start).compactMap(\.value.first)
        return unique
            .filter { event in
                guard !event.isAllDay else { return false }
                guard event.start >= window.start, event.start < window.end else { return false }
                return calendar.component(.hour, from: event.start) < ZoonTomorrow.latestMorningEventHour
            }
            .sorted { $0.start < $1.start }
            .first
    }
}

/// A Calendar-derived commitment Zoon has written down, plus the context
/// that says when it stops being true.
///
/// This is deliberately *not* the same persistence model as the manual
/// commitment. A manual time is a standing intent — "I want to be sharp at
/// 8:30" — and repeats until the person changes it. A Calendar event is a
/// fact about one specific day, and storing only its hour and minute (which
/// is what Zoon used to do) means tomorrow's 8:30 meeting silently becomes
/// the day after's, and the day after that's, forever, long after the event
/// itself is gone.
struct StoredCommitment: Codable, Hashable, Sendable {
    /// The actual instant, not an hour-and-minute. A timezone change moves
    /// the local clock reading; it does not move the event.
    var start: Date
    var isAllDay: Bool
    /// Opaque EventKit identifier when available. No title, ever.
    var eventIdentifier: String?
    /// When this was read out of EventKit.
    var fetchedAt: Date
    /// The timezone the read happened in, for provenance. Validity is decided
    /// from `start` against the current calendar, so this is not load-bearing
    /// — it is here so a support question about a travel day is answerable.
    var timeZoneIdentifier: String

    init(
        start: Date,
        isAllDay: Bool,
        eventIdentifier: String? = nil,
        fetchedAt: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.start = start
        self.isAllDay = isAllDay
        self.eventIdentifier = eventIdentifier
        self.fetchedAt = fetchedAt
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(commitment: CalendarCommitment, fetchedAt: Date, timeZone: TimeZone = .current) {
        self.init(
            start: commitment.start,
            isAllDay: commitment.isAllDay,
            eventIdentifier: commitment.eventIdentifier,
            fetchedAt: fetchedAt,
            timeZoneIdentifier: timeZone.identifier
        )
    }
}

/// A standing morning time the person set themselves.
struct ManualCommitment: Hashable, Sendable {
    var hour: Int
    var minute: Int

    /// Where this time lands on the morning being planned for.
    func start(now: Date, calendar: Calendar = .current) -> Date? {
        guard let window = PlanningDay.morning(after: now, calendar: calendar) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: window.start)
    }
}

/// Decides which commitment — if any — tonight's plan should be built around.
///
/// The two sources are resolved separately and only then compared, which is
/// the whole point: a Calendar record that no longer describes the morning
/// being planned is dropped rather than reinterpreted, and dropping it falls
/// back to the manual intent instead of to a fabricated event.
enum CommitmentResolver {

    /// How old a stored Calendar read may be before it is no longer trusted.
    ///
    /// The read runs when Tomorrow or Today appears, so in ordinary use the
    /// record is minutes old. This bound exists for the case where it does
    /// not run — permission revoked, Calendar app uninstalled, the app opened
    /// straight into a different tab — so an unrefreshed record cannot go on
    /// asserting a commitment nobody has re-checked.
    static let maximumCalendarAge: TimeInterval = 14 * 3600

    enum Outcome: Hashable, Sendable {
        case calendar(ZoonTomorrow.Event)
        case manual(ZoonTomorrow.Event)
        /// Named rather than `none`, which would collide with `Optional.none`
        /// at every call site that compares against it.
        case noCommitment

        var event: ZoonTomorrow.Event? {
            switch self {
            case let .calendar(event), let .manual(event): event
            case .noCommitment: nil
            }
        }
    }

    /// Whether a stored Calendar record still describes the morning being
    /// planned for.
    ///
    /// Every clause is a way a previously-true record goes stale: the event
    /// was deleted (no refresh lands, so age catches it), moved to another
    /// day, moved past the morning cutoff, moved into the past, or the device
    /// travelled far enough that the instant is no longer on the local
    /// morning at all.
    static func isStillValid(_ stored: StoredCommitment, now: Date, calendar: Calendar = .current) -> Bool {
        guard !stored.isAllDay else { return false }
        guard stored.fetchedAt <= now else { return false }
        guard now.timeIntervalSince(stored.fetchedAt) <= maximumCalendarAge else { return false }
        guard stored.start > now else { return false }
        guard let window = PlanningDay.morning(after: now, calendar: calendar) else { return false }
        guard stored.start >= window.start, stored.start < window.end else { return false }
        return calendar.component(.hour, from: stored.start) < ZoonTomorrow.latestMorningEventHour
    }

    /// The commitment tonight's plan should use.
    ///
    /// When both a valid Calendar record and an enabled manual time exist,
    /// the earlier one wins: both are obligations, and the binding one is
    /// whichever the person has to be ready for first. Ties go to Calendar,
    /// because it is the dated one.
    static func resolve(
        calendarRecord: StoredCommitment?,
        manual: ManualCommitment?,
        now: Date,
        calendar: Calendar = .current
    ) -> Outcome {
        let calendarStart = calendarRecord
            .flatMap { isStillValid($0, now: now, calendar: calendar) ? $0.start : nil }
        let manualStart = manual?.start(now: now, calendar: calendar)

        switch (calendarStart, manualStart) {
        case let (.some(fromCalendar), .some(fromManual)):
            return fromManual < fromCalendar
                ? .manual(ZoonTomorrow.Event(start: fromManual, isAllDay: false, source: .manual))
                : .calendar(ZoonTomorrow.Event(start: fromCalendar, isAllDay: false, source: .calendar))
        case let (.some(fromCalendar), nil):
            return .calendar(ZoonTomorrow.Event(start: fromCalendar, isAllDay: false, source: .calendar))
        case let (nil, .some(fromManual)):
            return .manual(ZoonTomorrow.Event(start: fromManual, isAllDay: false, source: .manual))
        case (nil, nil):
            return .noCommitment
        }
    }
}
