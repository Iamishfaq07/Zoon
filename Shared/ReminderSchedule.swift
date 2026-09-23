import Foundation

/// Turns resolved sleep episodes into dated, one-off notification requests.
///
/// **The defect this replaces.** Every reminder was a
/// `UNCalendarNotificationTrigger` built from only the hour and minute of one
/// `Date`, with `repeats: true`. That fires every day at that clock time, so:
///
/// - a Tuesday-only plan alerted on Wednesday, and every day after;
/// - a one-night override became a permanent daily alert;
/// - a travel or shift night's time kept firing after the trip ended.
///
/// Repeating was chosen so the reminder survives the app staying closed. A
/// bounded horizon of dated requests keeps that property -- `horizonNights`
/// nights are queued ahead -- without making any one night's time permanent.
/// The trade is stated rather than hidden: if the app is not opened for
/// longer than the horizon, reminders stop rather than fire at a stale time,
/// and Settings says through which date they are scheduled.
///
/// **Identifiers are slots, not dates.** `kind.prefix + index`, so replacing
/// the schedule and cancelling it both know every identifier that could exist
/// without asking the notification center what is pending -- and a
/// reschedule can never leave yesterday's requests behind to accumulate.
enum ReminderSchedule {

    /// Nights queued ahead. Seven nights of four kinds is 28 requests,
    /// comfortably inside iOS's 64 pending local notifications per app.
    static let horizonNights = 7

    enum Kind: String, CaseIterable, Sendable {
        case windDown
        case bedtime
        case wakeWindow
        case morningBrief

        var prefix: String { "zoon.reminder.\(rawValue.lowercased())." }

        /// The single fixed identifier the repeating implementation used.
        /// Cancelled on every reschedule, so an install upgraded from that
        /// version does not keep its old daily request firing forever next
        /// to the new dated ones.
        var legacyIdentifier: String { "zoon.reminder.\(rawValue.lowercased())" }

        /// Every identifier this kind can occupy.
        var allIdentifiers: [String] {
            [legacyIdentifier] + (0..<ReminderSchedule.horizonNights).map { "\(prefix)\($0)" }
        }
    }

    struct Request: Hashable, Sendable {
        let identifier: String
        let kind: Kind
        let fireDate: Date
        /// Full date components, including the zone, for a non-repeating
        /// calendar trigger. Year, month and day are what make it one-off.
        let components: DateComponents
    }

    /// Dated requests for one kind, one per fire date still in the future.
    ///
    /// Past dates are dropped rather than scheduled: a trigger whose date has
    /// passed never fires, and recording it as scheduled would be claiming
    /// something is armed that is not. Duplicate dates (two episodes that
    /// resolve to the same minute) collapse to one.
    static func requests(
        kind: Kind,
        fireDates: [Date],
        now: Date,
        calendar: Calendar = .current
    ) -> [Request] {
        var seen = Set<Int>()
        let future = fireDates
            .filter { $0 > now }
            .sorted()
            .filter { seen.insert(Int($0.timeIntervalSince1970 / 60)).inserted }
            .prefix(horizonNights)
        return future.enumerated().map { index, date in
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            components.timeZone = calendar.timeZone
            components.calendar = calendar
            return Request(
                identifier: "\(kind.prefix)\(index)",
                kind: kind,
                fireDate: date,
                components: components
            )
        }
    }

    /// The fire dates each kind uses, from the episodes.
    static func fireDates(
        for kind: Kind,
        episodes: [ResolvedSleepEpisode],
        wakeWindowLeadMinutes: Int,
        morningBriefLeadMinutes: Int
    ) -> [Date] {
        episodes.map { episode in
            switch kind {
            case .windDown: episode.windDown
            case .bedtime: episode.bed
            case .wakeWindow: episode.wake.addingTimeInterval(-Double(wakeWindowLeadMinutes) * 60)
            case .morningBrief: episode.wake.addingTimeInterval(Double(morningBriefLeadMinutes) * 60)
            }
        }
    }
}
