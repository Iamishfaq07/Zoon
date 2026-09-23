import Foundation
import UserNotifications
import os

/// Local notifications for wind-down and bedtime.
///
/// Every competitor has this and it is the one feature that acts *before* the
/// night rather than reporting on it afterwards. A sleep app that only ever
/// tells you what already went wrong is a scoreboard, not a coach.
///
/// ## Local only
///
/// `UNUserNotificationCenter` schedules on device. There is no push
/// certificate, no APNs registration, and no server — which matters twice
/// here: it keeps the no-network promise intact, and push entitlements are
/// paid-account-only, so a remote implementation could not ship without one.
///
/// ## Dated, not repeating
///
/// These used to be `UNCalendarNotificationTrigger`s with `repeats: true`,
/// built from only the hour and minute of one night. That turned a
/// Tuesday-only plan into a daily alert and a one-night override into a
/// permanent one. Each night is now its own dated request, queued
/// `ReminderSchedule.horizonNights` ahead so an app nobody opens still
/// reminds them -- see `ReminderSchedule` for the trade that makes.
@MainActor
@Observable
final class BedtimeReminder {

    /// Mirrors the system's authorisation so the UI can explain itself rather
    /// than showing a toggle that silently does nothing.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "Reminders")

    /// How long before target bedtime the wind-down nudge fires.
    ///
    /// Thirty minutes because that is roughly where the evidence on screens,
    /// light and caffeine stops being a nudge and starts being a countdown —
    /// and because a warning that arrives five minutes before is useless.
    static let windDownLeadMinutes = 30

    /// How long after usual wake the morning-brief nudge fires.
    ///
    /// Half an hour: early enough that the brief is still the first thing
    /// people would have opened the app for, late enough that it is not
    /// another alarm.
    static let morningBriefLeadMinutes = 30

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Authorisation

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
    }

    /// Returns `true` if notifications can now be posted.
    ///
    /// Deliberately not called on launch. Asking for notification permission
    /// before the user has expressed any interest is the single most reliable
    /// way to get permanently denied — it is requested from Settings, at the
    /// moment the user turns the feature on.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
            return granted
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            await refreshAuthorization()
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedules (or reschedules) both reminders for a nightly bedtime.
    ///
    /// Queues wind-down and bedtime for each bedtime given, replacing
    /// whatever was queued before.
    ///
    /// Idempotent: identifiers are slots, and every slot is cleared first,
    /// so rescheduling replaces rather than accumulates.
    /// - Returns: whether every request was accepted, and at least one was
    ///   made. Reported rather than swallowed so `ScheduleStateStore` can
    ///   record `.failed` instead of claiming something is armed when the OS
    ///   refused it -- or when every date had already passed.
    @discardableResult
    func schedule(bedtimes: [Date], now: Date = .now) async -> Bool {
        cancel()
        guard isAuthorized else {
            logger.notice("Not authorized; nothing scheduled")
            return false
        }
        let windDowns = ReminderSchedule.requests(
            kind: .windDown,
            fireDates: bedtimes.map { $0.addingTimeInterval(-Double(Self.windDownLeadMinutes) * 60) },
            now: now
        )
        let beds = ReminderSchedule.requests(kind: .bedtime, fireDates: bedtimes, now: now)
        let windDownAdded = await add(
            windDowns,
            title: "Wind down",
            body: "Bedtime in \(Self.windDownLeadMinutes) minutes. Dim the lights and put the screens away."
        )
        let bedtimeAdded = await add(
            beds,
            title: "Bedtime",
            body: "Going to sleep now hits your full sleep need for tomorrow."
        )
        logger.info("Scheduled \(beds.count) bedtime reminder(s)")
        return !beds.isEmpty && windDownAdded && bedtimeAdded
    }

    /// One night only. Prefer `schedule(bedtimes:)` with the horizon.
    @discardableResult
    func schedule(bedtime: Date) async -> Bool {
        await schedule(bedtimes: [bedtime])
    }

    /// Notifies within a window before each wake time given.
    ///
    /// Deliberately not a "smart alarm" in the sense competitors use the
    /// term — those wake you at the lightest point in your sleep cycle,
    /// detected by watching motion in real time all night. Zoon has no live
    /// overnight sensing loop, and building one changes what kind of app
    /// this is. What this does instead: fire early, within `leadMinutes` of
    /// the planned wake, so there's a chance of catching a lighter stretch
    /// without claiming to have detected one.
    ///
    /// A notification, not an alarm: it follows the ringer switch and Focus,
    /// and is never described as something that will sound through them.
    @discardableResult
    func scheduleWakeWindow(wakeTimes: [Date], leadMinutes: Int, now: Date = .now) async -> Bool {
        cancelWakeWindow()
        guard isAuthorized else { return false }
        let requests = ReminderSchedule.requests(
            kind: .wakeWindow,
            fireDates: wakeTimes.map { $0.addingTimeInterval(-Double(leadMinutes) * 60) },
            now: now
        )
        let added = await add(
            requests,
            title: "Wake window",
            body: "Somewhere in the next \(leadMinutes) minutes is close to your planned wake time."
        )
        return !requests.isEmpty && added
    }

    /// A lock-screen-safe nudge pointing at Today's morning brief.
    ///
    /// Fires `leadMinutes` after each wake so it arrives once someone is
    /// actually up, not while they are still asleep. The body is run through
    /// `MorningBriefCopy` so a duration or score cannot leak onto a lock
    /// screen anyone in the room can read.
    @discardableResult
    func scheduleMorningBrief(
        wakeTimes: [Date],
        leadMinutes: Int = 30, // same value as morningBriefLeadMinutes; default args cannot mention Self
        actionableTip: String = "",
        now: Date = .now
    ) async -> Bool {
        cancelMorningBrief()
        guard isAuthorized else { return false }
        let requests = ReminderSchedule.requests(
            kind: .morningBrief,
            fireDates: wakeTimes.map { $0.addingTimeInterval(Double(leadMinutes) * 60) },
            now: now
        )
        let added = await add(
            requests,
            title: MorningBriefCopy.title,
            body: MorningBriefCopy.body(actionableTip: actionableTip)
        )
        return !requests.isEmpty && added
    }

    func cancelWakeWindow() {
        center.removePendingNotificationRequests(withIdentifiers: ReminderSchedule.Kind.wakeWindow.allIdentifiers)
    }

    func cancelMorningBrief() {
        center.removePendingNotificationRequests(withIdentifiers: ReminderSchedule.Kind.morningBrief.allIdentifiers)
    }

    func cancel() {
        center.removePendingNotificationRequests(
            withIdentifiers: ReminderSchedule.Kind.windDown.allIdentifiers
                + ReminderSchedule.Kind.bedtime.allIdentifiers
        )
    }

    private var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional
    }

    /// Adds every request; true only if all were accepted.
    private func add(_ requests: [ReminderSchedule.Request], title: String, body: String) async -> Bool {
        var allAdded = true
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // No health numbers in the payload. Notification text appears on a
            // locked screen, where anyone in the room can read it — "you slept
            // 4h12m" is not something to broadcast to a bedroom.
            content.interruptionLevel = .active

            let trigger = UNCalendarNotificationTrigger(dateMatching: request.components, repeats: false)
            do {
                try await center.add(
                    UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
                )
            } catch {
                allAdded = false
                logger.error("Could not schedule \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return allAdded
    }

    /// Human-readable state for Settings.
    var statusDescription: String {
        switch authorization {
        case .notDetermined: "Not set up yet."
        case .denied: "Turned off in iOS Settings → Notifications → Zoon."
        case .authorized: "On."
        case .provisional: "Delivering quietly."
        case .ephemeral: "Temporary access."
        @unknown default: "Unknown."
        }
    }
}
