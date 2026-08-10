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
/// ## Why calendar triggers rather than one-shot dates
///
/// A `UNCalendarNotificationTrigger` with `repeats: true` keeps firing without
/// the app ever running again. A date-based trigger would need rescheduling on
/// each launch, and an app you forget to open is exactly the app that most
/// needs the reminder.
@MainActor
@Observable
final class BedtimeReminder {

    /// Mirrors the system's authorisation so the UI can explain itself rather
    /// than showing a toggle that silently does nothing.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "Reminders")

    private enum ID {
        static let windDown = "zoon.reminder.winddown"
        static let bedtime = "zoon.reminder.bedtime"
        static let wakeWindow = "zoon.reminder.wakewindow"
    }

    /// How long before target bedtime the wind-down nudge fires.
    ///
    /// Thirty minutes because that is roughly where the evidence on screens,
    /// light and caffeine stops being a nudge and starts being a countdown —
    /// and because a warning that arrives five minutes before is useless.
    static let windDownLeadMinutes = 30

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
    /// Idempotent: identifiers are fixed, so re-scheduling replaces rather than
    /// accumulates. Getting this wrong is how apps end up firing six copies of
    /// the same notification.
    func schedule(bedtime: Date) async {
        cancel()

        guard authorization == .authorized || authorization == .provisional else {
            logger.notice("Not authorized; nothing scheduled")
            return
        }

        let calendar = Calendar.current
        let bedComponents = calendar.dateComponents([.hour, .minute], from: bedtime)
        let windDown = bedtime.addingTimeInterval(-Double(Self.windDownLeadMinutes) * 60)
        let windComponents = calendar.dateComponents([.hour, .minute], from: windDown)

        await add(
            id: ID.windDown,
            title: "Wind down",
            body: "Bedtime in \(Self.windDownLeadMinutes) minutes. Dim the lights and put the screens away.",
            components: windComponents
        )

        await add(
            id: ID.bedtime,
            title: "Bedtime",
            body: "Going to sleep now hits your full sleep need for tomorrow.",
            components: bedComponents
        )

        logger.info("Scheduled wind-down and bedtime reminders")
    }

    /// Notifies within a window before your usual wake time, derived from
    /// `BodyClock`.
    ///
    /// Deliberately not a "smart alarm" in the sense competitors use the
    /// term — those wake you at the lightest point in your sleep cycle,
    /// detected by watching motion in real time all night. Zoon has no live
    /// overnight sensing loop, and building one changes what kind of app
    /// this is. What this does instead: fire early, within `leadMinutes` of
    /// the wake time your own history already points to, so there's a
    /// chance of catching a lighter stretch without claiming to have
    /// detected one.
    func scheduleWakeWindow(wakeTime: Date, leadMinutes: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [ID.wakeWindow])

        guard authorization == .authorized || authorization == .provisional else { return }

        let calendar = Calendar.current
        let early = wakeTime.addingTimeInterval(-Double(leadMinutes) * 60)
        let components = calendar.dateComponents([.hour, .minute], from: early)

        await add(
            id: ID.wakeWindow,
            title: "Wake window",
            body: "Somewhere in the next \(leadMinutes) minutes is close to your usual wake time.",
            components: components
        )
    }

    func cancelWakeWindow() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.wakeWindow])
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.windDown, ID.bedtime])
    }

    private func add(
        id: String,
        title: String,
        body: String,
        components: DateComponents
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // No health numbers in the payload. Notification text appears on a
        // locked screen, where anyone in the room can read it — "you slept
        // 4h12m" is not something to broadcast to a bedroom.
        content.interruptionLevel = .active

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            logger.error("Could not schedule \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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
