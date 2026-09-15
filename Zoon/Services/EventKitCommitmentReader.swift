import Foundation

#if canImport(EventKit)
import EventKit
#endif

/// Privacy-first Calendar reader. Titles are never copied out of EventKit.
///
/// Shared/ stays Foundation-only. This lives in the app target and returns
/// `CalendarCommitment` values that carry only a start time.
@MainActor
enum EventKitCommitmentReader {

    static func firstTomorrow(now: Date = .now, calendar: Calendar = .current) async -> CalendarCommitment? {
        #if canImport(EventKit)
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            do {
                granted = try await store.requestFullAccessToEvents()
            } catch {
                return nil
            }
        } else {
            return nil
        }
        guard granted else { return nil }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        let start = calendar.startOfDay(for: tomorrow)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
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
                source: .calendar
            )
        }
        return CalendarCommitmentPicker.firstMeaningful(in: events, after: now, calendar: calendar)
        #else
        return nil
        #endif
    }
}
