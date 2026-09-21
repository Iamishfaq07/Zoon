import Foundation
import UserNotifications
import os

/// Schedules and cancels the thing that actually wakes someone from a nap.
///
/// A protocol so `NapStore` can be tested without the notification centre.
/// Every method is `@MainActor` to match `NapStore`, which owns the calls.
@MainActor
protocol NapWakeScheduling: AnyObject {
    /// - Returns: how the wake was armed, so AlarmKit and a Focus-silenced
    ///   notification are never reported as the same thing.
    @discardableResult
    func schedule(at date: Date, targetMinutes: Int) async -> NapWakeKind
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

    init(center: UNUserNotificationCenter? = nil, alarm: WakeAlarm? = nil) {
        // Default arguments are evaluated in a nonisolated context, and
        // `WakeAlarm.init` is `@MainActor`. Construct inside this isolated
        // initializer instead of as a default value.
        self.center = center ?? .current()
        self.alarm = alarm ?? WakeAlarm()
    }

    @discardableResult
    func schedule(at date: Date, targetMinutes: Int) async -> NapWakeKind {
        cancel()

        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else {
            logger.notice("Nap target is already past; nothing scheduled")
            return .unavailable
        }

        if alarm.isAvailable {
            let authorized = await alarm.requestAuthorization()
            if authorized, await alarm.schedule(at: date, slot: .nap) {
                logger.info("Nap AlarmKit slot armed")
                return .alarmKit
            }
        }

        if await scheduleNotification(seconds: seconds, targetMinutes: targetMinutes) {
            return .notification
        }
        return .unavailable
    }

    func cancel() {
        _ = alarm.cancel(slot: .nap)
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    private func scheduleNotification(seconds: TimeInterval, targetMinutes: Int) async -> Bool {
        let settings = await center.notificationSettings()
        var permitted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        if !permitted {
            do {
                permitted = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                logger.notice("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
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
