import Foundation
import UserNotifications
import os

/// Schedules and cancels the thing that actually wakes someone from a nap.
///
/// A protocol so `NapStore` can be tested without the notification centre.
/// Every method is `@MainActor` to match `NapStore`, which owns the calls.
@MainActor
protocol NapWakeScheduling: AnyObject {
    /// - Returns: whether the request was accepted, so a refusal can be
    ///   recorded rather than reported as armed.
    @discardableResult
    func schedule(at date: Date, targetMinutes: Int) async -> Bool
    func cancel()
}

/// A local notification at a nap's target end.
///
/// Before this existed, nothing woke anyone. `NapStore` started a Live
/// Activity -- a countdown you could look at -- and `NapView` ran a
/// one-second `Task` that recomputed a progress ring. Neither fires at the
/// target, and the `Task` does not exist while the screen is off. A nap timer
/// was a stopwatch you had to watch, which is the one thing a nap timer must
/// not be.
///
/// ## Why a notification rather than AlarmKit
///
/// `WakeAlarm` already wraps AlarmKit, and AlarmKit is the better mechanism:
/// it rings through silent mode and Focus, which is exactly what an alarm is
/// for. It is deliberately not reused here.
///
/// `WakeAlarm` models a single alarm -- the morning wake -- and holds one
/// `scheduledWakeTime` for it. Sharing it would mean a nap and the morning
/// alarm overwriting each other, so nap support needs a second alarm identity
/// inside that type. That is a real change to code whose own documentation
/// records that it has never run against AlarmKit on a device, and there is
/// no Apple hardware in this workflow to verify it on. Shipping an untested
/// second path through an unverified integration would trade a known gap for
/// an unknown one.
///
/// So this closes the actual gap -- there was no wake at all -- with the
/// mechanism that works on every supported OS and can be reasoned about.
///
/// ## What that costs, stated plainly
///
/// `interruptionLevel` is `.active`, matching `BedtimeReminder`, because Zoon
/// does not hold the `com.apple.developer.usernotifications.time-sensitive`
/// entitlement. **A Focus or Do Not Disturb will silence this.** Fixing it
/// properly means either that entitlement or the AlarmKit path above; both
/// are provisioning decisions rather than code ones. `NapView` should not
/// imply the nap alarm is louder than it is.
@MainActor
final class NapWake: NapWakeScheduling {

    /// One identifier, so re-scheduling replaces rather than accumulates.
    /// Getting this wrong is how apps end up firing six copies of the same
    /// notification.
    static let identifier = "zoon.nap.wake"

    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "NapWake")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    @discardableResult
    func schedule(at date: Date, targetMinutes: Int) async -> Bool {
        cancel()

        let settings = await center.notificationSettings()
        let permitted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        guard permitted else {
            // Deliberately not a permission prompt. A nap is started with one
            // tap and the prompt would land on top of the timer; notification
            // permission is requested from Settings, where the user is
            // already deciding about reminders.
            logger.notice("Not authorized; no nap wake scheduled")
            return false
        }

        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else {
            logger.notice("Nap target is already past; nothing scheduled")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Nap over"
        content.body = "Your \(targetMinutes)-minute nap is up."
        content.sound = .default
        // No health numbers in the payload, same rule as `BedtimeReminder`:
        // notification text appears on a locked screen where anyone in the
        // room can read it.
        content.interruptionLevel = .active

        // Time-interval rather than calendar: the target is an instant, not a
        // wall-clock time that should survive a timezone change, and a nap
        // crossing a DST boundary should still end after the number of
        // minutes it was set for.
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        do {
            try await center.add(request)
            return true
        } catch {
            logger.error("Could not schedule nap wake: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        // Also clears one that already fired, so a stale "Nap over" banner
        // is not sitting in Notification Centre after the nap was cancelled.
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}
