import Foundation

#if canImport(EventKit)
import EventKit
#endif

/// Privacy-first Calendar reader. Titles are never copied out of EventKit.
///
/// Shared/ stays Foundation-only. This lives in the app target and returns
/// `CalendarCommitment` values that carry only a start time and an opaque
/// identifier.
@MainActor
enum EventKitCommitmentReader {

    /// The outcome of a read, which is not the same thing as a commitment.
    ///
    /// `.read(nil)` — permission granted, day inspected, nothing qualifying —
    /// is the case the old `CalendarCommitment?` return type could not
    /// express, and conflating it with `.unavailable` is what let a deleted
    /// event go on living in storage: the caller could not tell "there is no
    /// meeting tomorrow" (clear the record) from "I could not look" (leave it
    /// alone).
    enum Outcome: Sendable {
        case read(CalendarCommitment?)
        case unavailable
    }

    static func firstTomorrow(now: Date = .now, calendar: Calendar = .current) async -> Outcome {
        #if canImport(EventKit)
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            do {
                granted = try await store.requestFullAccessToEvents()
            } catch {
                return .unavailable
            }
        } else {
            return .unavailable
        }
        guard granted else { return .unavailable }

        // The same window the picker and the stored-record expiry check use.
        // Three different definitions of "tomorrow" is how a commitment gets
        // written under one and read back under another.
        guard let window = PlanningDay.morning(after: now, calendar: calendar) else { return .unavailable }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        // `startDate` and `endDate` are implicitly-unwrapped optionals on
        // `EKEvent`: EventKit declares them non-null but they are bridged from
        // Objective-C and a malformed or partially-synced event can hand back
        // nil, which would trap here rather than skip one row. This is the
        // only new path in the app reading data another application wrote, so
        // it gets the guard rather than the assumption.
        //
        // `compactMap`, so an unusable event is dropped and the rest of
        // tomorrow still produces a plan.
        let events = store.events(matching: predicate).compactMap { event -> CalendarCommitment? in
            guard let start = event.startDate as Date? else { return nil }
            let end = event.endDate as Date?
            return CalendarCommitment(
                start: start,
                // A missing end is a zero-length commitment rather than a
                // dropped one: the start time is what anchors wake, and that
                // is the field this reader exists for.
                durationMinutes: max(0, (end?.timeIntervalSince(start) ?? 0) / 60),
                isAllDay: event.isAllDay,
                source: .calendar,
                // Shared across occurrences of a recurring event, so it is
                // provenance rather than a key: whether a stored record is
                // still current is decided from its start instant, which is
                // per-occurrence. Kept because "is this the same meeting that
                // moved, or a different one?" is otherwise unanswerable.
                eventIdentifier: event.eventIdentifier
            )
        }
        return .read(CalendarCommitmentPicker.firstMeaningful(in: events, after: now, calendar: calendar))
        #else
        return .unavailable
        #endif
    }

    /// The first morning commitment on each of the next `days` days, keyed by
    /// the start of the local day it falls on.
    ///
    /// For the Sleep Runway, which needs a horizon rather than one night.
    /// Read live and never persisted: `StoredCommitment` deliberately holds
    /// exactly one dated record with expiry semantics, and a second store
    /// keyed by day would be a second thing that can go stale — which is the
    /// bug that model exists to prevent. A planning screen can afford to ask
    /// EventKit when it appears.
    ///
    /// Still only start times. No titles, no attendees, nothing persisted.
    static func mornings(
        through days: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> [Date: Date] {
        #if canImport(EventKit)
        let store = EKEventStore()
        guard #available(iOS 17.0, *),
              let granted = try? await store.requestFullAccessToEvents(), granted,
              let firstMorning = PlanningDay.morning(after: now, calendar: calendar)?.start,
              let end = calendar.date(byAdding: .day, value: days, to: firstMorning)
        else { return [:] }

        let predicate = store.predicateForEvents(withStart: firstMorning, end: end, calendars: nil)
        var earliest: [Date: Date] = [:]
        for event in store.events(matching: predicate) {
            guard !event.isAllDay, let start = event.startDate as Date? else { continue }
            guard calendar.component(.hour, from: start) < ZoonTomorrow.latestMorningEventHour else { continue }
            let day = calendar.startOfDay(for: start)
            if let existing = earliest[day], existing <= start { continue }
            earliest[day] = start
        }
        return earliest
        #else
        return [:]
        #endif
    }
}
