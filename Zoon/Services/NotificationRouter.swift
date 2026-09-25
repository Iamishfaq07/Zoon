import Foundation
import UserNotifications

/// Identifiers for the reminders' action buttons. An enum rather than
/// constants on `BedtimeReminder`, which is `@MainActor`: the delegate below
/// reads them off the main actor.
enum ReminderNotification {
    /// The evening wind-down reminder's category.
    static let windDownCategory = "zoon.reminder.windDown"
    /// Its "Start wind down" button.
    static let startWindDownAction = "zoon.reminder.startWindDown"
}

/// Handles taps on Zoon's local notifications, and shows a reminder that
/// fires while the app is open.
///
/// Without a delegate iOS drops a notification that arrives while the app is
/// in front -- a wind-down reminder at 22:15 with Zoon open said nothing --
/// and an action button has nowhere to report its tap.
///
/// The button hands off the same way Siri's Start Wind Down does: a pending
/// destination plus the start flag, which `RootView.consumeDeepLink` acts on.
/// The tap can arrive after the app is already active, so the router also
/// posts `deepLinkPosted` for `RootView` to consume immediately.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, Sendable {

    static let shared = NotificationRouter()

    static let deepLinkPosted = Notification.Name("zoon.notificationRouter.deepLinkPosted")

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == ReminderNotification.startWindDownAction else { return }
        DeepLink.pending = .windDown
        DeepLink.pendingStartsWindDown = true
        await MainActor.run {
            NotificationCenter.default.post(name: Self.deepLinkPosted, object: nil)
        }
    }
}
