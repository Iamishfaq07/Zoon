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

/// Wakes someone from a nap.
///
/// Prefers AlarmKit through `WakeAlarm.Slot.nap`, which is a distinct
/// identity from the morning wake so the two cannot overwrite each other.
/// When AlarmKit is unavailable, unauthorized, or fails to schedule, this
/// falls back to a local notification. Focus / Do Not Disturb can silence
/// that fallback; the UI must not imply it is louder than it is.
@MainActor
final class NapWake: NapWakeScheduling {

    /// One identifier, so re-scheduling replaces rather than accumulates.
    static let identifier = "zoon.nap.wake"

    private let center: UNUserNotificationCenter
    private let alarm: WakeAlarm
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "NapWake")

    init(center: UNUserNotificationCenter = .current(), alarm: WakeAlarm = WakeAlarm()) {
        self.center = center
        self.alarm = alarm
    }

    @discardableResult
    func schedule(at date: Date, targetMinutes: Int) async -> Bool {
        cancel()

        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else {
            logger.notice("Nap target is already past; nothing scheduled")
            return false
        }

        if await alarm.schedule(at: date, slot: .nap) {
            logger.info("Nap AlarmKit slot armed")
            return true
        }

        return await scheduleNotification(seconds: seconds, targetMinutes: targetMinutes)
    }

    func cancel() {
        _ = alarm.cancel(slot: .nap)
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    private func scheduleNotification(seconds: TimeInterval, targetMinutes: Int) async -> Bool {
        let settings = await center.notificationSettings()
        let permitted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        guard permitted else {
            logger.notice("Not authorized; no nap wake scheduled")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Nap over"
        content.body = "Your \(targetMinutes)-minute nap is up."
        content.sound = .default
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        do {
            try await center.add(request)
            logger.notice("Nap wake fell back to a notification; Focus may silence it")
            return true
        } catch {
            logger.error("Could not schedule nap wake: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
