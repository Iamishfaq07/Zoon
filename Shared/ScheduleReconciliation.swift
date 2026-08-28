import Foundation

/// Decides what to do about one scheduled thing, given what Zoon *wants*
/// scheduled and what it last actually scheduled.
///
/// This exists because the previous logic asked the wrong question. It was
/// shaped as "if the feature is switched on, schedule it", with cancellation
/// living in the `else` of a `guard` that also covered the target being
/// unavailable:
///
/// ```swift
/// guard preferences.smartWakeEnabled, let wakeTime = ... else {
///     if !preferences.smartWakeEnabled { cancel() }   // <- only this branch
///     return
/// }
/// ```
///
/// So when the feature stayed on but the target went away -- no body clock
/// yet, HealthKit access revoked, history pruned below the window -- neither
/// arm of that `if` fired and a previously scheduled reminder was left armed
/// at its old time. `BedtimeReminder` schedules with
/// `UNCalendarNotificationTrigger(repeats: true)`, so the consequence was not
/// one stale notification but one *every day*, indefinitely, at a time Zoon
/// no longer believed in.
///
/// The fix is to stop treating "switched off" and "nothing to schedule" as
/// different cases. Both mean the desired schedule is `nil`, and anything
/// currently scheduled has to go.
enum ScheduleReconciliation {

    /// What has to happen to bring the system in line with intent.
    enum Action: Equatable, Sendable {
        /// Already correct. Deliberately distinct from `replace` with the
        /// same date: re-adding an identical `UNNotificationRequest` is
        /// harmless but re-adding an identical *alarm* is not necessarily,
        /// and a no-op that reports itself as one is also what makes
        /// "scheduled twice" visible in a test.
        case noChange
        /// Something is scheduled that should not be.
        case cancel
        /// Schedule this, replacing whatever is there.
        case replace(Date)
    }

    /// How far apart two times have to be before rescheduling is worth it.
    ///
    /// A minute, because the desired time is derived from a rolling body-clock
    /// estimate that drifts by seconds between refreshes. Without a tolerance
    /// every foreground activation would cancel and re-add the same
    /// notification, which is both pointless and a good way to lose a
    /// pending trigger to a race.
    static let defaultTolerance: TimeInterval = 60

    /// - Parameters:
    ///   - desired: the time Zoon wants scheduled, or `nil` when it wants
    ///     nothing scheduled -- whether because the user switched the feature
    ///     off *or* because there is no longer a target to schedule against.
    ///     Collapsing those two into one input is the whole point.
    ///   - scheduled: the time Zoon last recorded as actually scheduled, or
    ///     `nil` if nothing is.
    static func action(
        desired: Date?,
        scheduled: Date?,
        tolerance: TimeInterval = defaultTolerance
    ) -> Action {
        switch (desired, scheduled) {
        case (nil, nil):
            return .noChange
        case (nil, _?):
            return .cancel
        case (let desired?, nil):
            return .replace(desired)
        case (let desired?, let scheduled?):
            let drift = abs(desired.timeIntervalSince(scheduled))
            return drift <= tolerance ? .noChange : .replace(desired)
        }
    }

    /// What Zoon can honestly claim about a slot, independent of whether any
    /// side effect was needed this pass.
    ///
    /// Kept separate from `action` because the two answer different
    /// questions, and conflating them is what produced the bug: a slot can
    /// need no action (nothing scheduled, nothing to schedule) while still
    /// not being in the state the user thinks it is (`unavailable`, not
    /// `notScheduled`). The toggle says on; there is simply no target.
    ///
    /// - Parameters:
    ///   - wanted: the user has this switched on.
    ///   - permitted: the OS has granted what this needs.
    ///   - hasTarget: a concrete time exists to schedule against.
    static func status(wanted: Bool, permitted: Bool, hasTarget: Bool) -> ScheduleStatus {
        guard wanted else { return .notScheduled }
        guard permitted else { return .needsPermission }
        return hasTarget ? .scheduled : .unavailable
    }
}

/// What Zoon can honestly say about one scheduled thing.
///
/// Persisted alongside the scheduled time so Settings can describe the real
/// state instead of echoing the toggle back at the user. A toggle that reads
/// "on" while nothing is scheduled -- because permission was revoked in iOS
/// Settings, or because the body clock has no window yet -- is the failure
/// this exists to make visible.
enum ScheduleStatus: String, Codable, Sendable, CaseIterable {

    /// Nothing scheduled, and nothing should be.
    case notScheduled

    /// Armed, at the recorded time.
    case scheduled

    /// The user wants this, but the OS has not granted what it needs.
    case needsPermission

    /// The user wants this, permission exists, but there is no target to
    /// schedule against -- no body-clock window yet, or not enough history.
    case unavailable

    /// The OS refused the request for some other reason. Distinct from
    /// `unavailable` because there is nothing the user can do about it and
    /// the copy should not imply otherwise.
    case failed

    var label: String {
        switch self {
        case .notScheduled: "Not scheduled"
        case .scheduled: "Scheduled"
        case .needsPermission: "Needs permission"
        case .unavailable: "Unavailable"
        case .failed: "Failed"
        }
    }

    /// Whether this state is one the user could act on. Drives whether the
    /// row offers a next step or just states a fact.
    var isActionable: Bool {
        self == .needsPermission
    }
}
