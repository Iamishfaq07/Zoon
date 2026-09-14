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
        let events = store.events(matching: predicate).map { event in
            CalendarCommitment(
                start: event.startDate,
                durationMinutes: event.endDate.timeIntervalSince(event.startDate) / 60,
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
