import Foundation
import os

#if canImport(AlarmKit)
import AlarmKit
import AppIntents
#else
// Same self-reporting guard the ActivityKit and FoundationModels paths use:
// without the framework this is a permanent no-op, and nothing at runtime
// would otherwise say why the alarm never rings.
#warning("AlarmKit unavailable: the wake alarm falls back to a notification in this build.")
#endif

/// A real alarm for the wake window — one that rings through silent mode and
/// a Sleep Focus, the way the system Clock app does.
///
/// ## Why this exists alongside `BedtimeReminder.scheduleWakeWindow`
///
/// That one schedules a `UNNotificationRequest`, and a notification is not an
/// alarm: it respects the ringer switch and Focus, so on the exact
/// configuration most people sleep in — phone silenced, Sleep Focus on — it
/// makes no sound at all. It was honest as a *nudge* for someone already
/// stirring, and it is still that on iOS 18. But anyone who read "wake
/// window" and trusted it to wake them was trusting something the API could
/// not do. AlarmKit (iOS 26) is the first time an app other than Clock can
/// schedule something that actually breaks through.
///
/// ## What this deliberately still isn't
///
/// Not a "smart alarm" that wakes you at the lightest point in your sleep
/// cycle. That needs a live overnight sensing loop Zoon doesn't have and
/// isn't going to grow; see `scheduleWakeWindow`'s note. This rings at a
/// fixed time derived from your own history — the same time the notification
/// would have fired — it just actually rings.
///
/// ## Availability
///
/// The whole surface is behind `#if canImport(AlarmKit)` so the file compiles
/// on an SDK without it, and behind a runtime `#available` check because the
/// deployment target is iOS 18: a binary built with the iOS 26 SDK still has
/// to run on a phone that has never heard of AlarmKit. On both of those
/// paths every method here is a no-op that reports `false`, and the caller
/// keeps the existing notification.
@MainActor
@Observable
final class WakeAlarm {

    /// Stable across schedulings so a re-schedule replaces the previous alarm
    /// rather than stacking a second one on the same morning.
    private static let alarmID = UUID(uuidString: "5F3B9A61-0C4E-4E7A-9E2D-1A7C6B8D4E20")!

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "WakeAlarm")

    /// Why a real alarm can't be scheduled right now, or `nil` if it can.
    /// Surfaced in Settings for the same reason `FoundationModelInsightEngine`
    /// surfaces its own: a toggle that silently does nothing is worse than one
    /// that explains itself.
    var unavailabilityReason: String? {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else {
            return "Needs iOS 26 or later. Until then the wake window is a notification, which won't sound in Silent mode."
        }
        return nil
        #else
        return "This build was compiled without AlarmKit."
        #endif
    }

    var isAvailable: Bool { unavailabilityReason == nil }

    /// Asks for permission to schedule alarms. Returns `true` only on an
    /// explicit grant, matching `SnoreDetector.requestPermission` and
    /// `BedtimeReminder.requestAuthorization` — asked for when the user turns
    /// the feature on, never at launch.
    func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return false }
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        } catch {
            logger.error("Alarm authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Restores across separate `WakeAlarm` instances (`RootView` and
    /// `SettingsView` each own one -- see this type's doc comment) so
    /// Settings can show what the alarm is actually set for without
    /// querying AlarmKit's own store directly. Set on every successful
    /// `schedule(at:)`, cleared on `cancel()`.
    private static let scheduledWakeTimeKey = "zoon.wakeAlarm.scheduledWakeTime"

    private(set) var scheduledWakeTime: Date? {
        didSet {
            if let scheduledWakeTime {
                UserDefaults.standard.set(scheduledWakeTime, forKey: Self.scheduledWakeTimeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.scheduledWakeTimeKey)
            }
        }
    }

    init() {
        scheduledWakeTime = UserDefaults.standard.object(forKey: Self.scheduledWakeTimeKey) as? Date
    }

    /// Schedules the wake alarm for `wakeTime`, replacing any previously
    /// scheduled one.
    ///
    /// A one-shot alarm at this exact moment (`.fixed`), not a repeating
    /// one. `wakeTime` is this specific night's personalized wake time and
    /// is recomputed and rescheduled on every foreground activation (see
    /// `RootView.refreshReminders`) -- a *repeating* weekly alarm at
    /// whatever hour/minute happened to be current the last time the app
    /// was opened would keep ringing at that stale time every day the app
    /// stayed closed, which is a real alarm going off at the wrong time
    /// rather than merely a missed update.
    ///
    /// - Returns: `true` when a real alarm is now set. `false` means the
    ///   caller should keep relying on the notification — this must never
    ///   silently swallow a failure, because the failure mode is somebody
    ///   oversleeping.
    @discardableResult
    func schedule(at wakeTime: Date) async -> Bool {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return false }

        do {
            let schedule = Alarm.Schedule.fixed(wakeTime)

            // AlarmButton is a value describing a button's label, not an
            // enum with pre-built cases -- "stop" is a role every alarm's
            // presentation constructs by hand.
            let stopButton = AlarmButton(
                text: "Stop",
                textColor: .white,
                systemImageName: "stop.fill"
            )
            let alert = AlarmPresentation.Alert(
                title: "Wake window",
                stopButton: stopButton
            )

            let attributes = AlarmAttributes<EmptyAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert),
                tintColor: .indigo
            )

            // Nested under AlarmManager, not a top-level type -- this is what
            // "cannot find 'AlarmConfiguration' in scope" meant on the first
            // compile.
            let configuration = AlarmManager.AlarmConfiguration<EmptyAlarmMetadata>(
                schedule: schedule,
                attributes: attributes
            )

            _ = try await AlarmManager.shared.schedule(id: Self.alarmID, configuration: configuration)
            logger.info("Wake alarm scheduled for \(wakeTime.formatted(.dateTime.hour().minute()))")
            scheduledWakeTime = wakeTime
            return true
        } catch {
            logger.error("Could not schedule wake alarm: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        return false
        #endif
    }

    func cancel() {
        scheduledWakeTime = nil
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        do {
            try AlarmManager.shared.cancel(id: Self.alarmID)
        } catch {
            logger.error("Could not cancel wake alarm: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}

#if canImport(AlarmKit)
/// AlarmKit's attributes type is generic over per-alarm metadata. Zoon has
/// exactly one alarm and needs to carry nothing alongside it, so this is the
/// empty conformance that satisfies the generic.
@available(iOS 26.0, *)
struct EmptyAlarmMetadata: AlarmMetadata {
    init() {}
}
#endif
