import XCTest

/// The decision table behind `RootView.refreshReminders`.
///
/// Extracted into a pure type specifically so the case that was broken can be
/// asserted. The old logic was shaped as
/// `guard enabled, let target else { if !enabled { cancel() } }`, which
/// cancels when the toggle goes off and does *nothing* when the target goes
/// away -- and since `BedtimeReminder` schedules with
/// `UNCalendarNotificationTrigger(repeats: true)`, "does nothing" meant a
/// notification every day, indefinitely, at a time Zoon no longer believed in.
final class ScheduleReconciliationTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Action

    func testNothingWantedAndNothingScheduledIsANoOp() {
        XCTAssertEqual(
            ScheduleReconciliation.action(desired: nil, scheduled: nil),
            .noChange
        )
    }

    /// The regression this file exists for.
    func testATargetThatDisappearsCancelsWhatWasScheduled() {
        XCTAssertEqual(
            ScheduleReconciliation.action(desired: nil, scheduled: noon),
            .cancel,
            "a scheduled reminder with no desired time must be cancelled, not left armed"
        )
    }

    func testAWantedTargetWithNothingScheduledSchedules() {
        XCTAssertEqual(
            ScheduleReconciliation.action(desired: noon, scheduled: nil),
            .replace(noon)
        )
    }

    func testAnUnchangedTargetIsNotRescheduled() {
        XCTAssertEqual(
            ScheduleReconciliation.action(desired: noon, scheduled: noon),
            .noChange
        )
    }

    /// The desired time comes from a rolling body-clock estimate that drifts
    /// by seconds between refreshes. Without a tolerance, every foreground
    /// activation would cancel and re-add the same notification.
    func testDriftInsideToleranceIsNotRescheduled() {
        XCTAssertEqual(
            ScheduleReconciliation.action(
                desired: noon.addingTimeInterval(30), scheduled: noon
            ),
            .noChange
        )
        XCTAssertEqual(
            ScheduleReconciliation.action(
                desired: noon.addingTimeInterval(-30), scheduled: noon
            ),
            .noChange
        )
    }

    func testARealChangeIsRescheduledOnce() {
        let moved = noon.addingTimeInterval(45 * 60)
        XCTAssertEqual(
            ScheduleReconciliation.action(desired: moved, scheduled: noon),
            .replace(moved)
        )
    }

    /// Applying the action twice must settle. A reconciler that always
    /// reports work to do reschedules on every activation forever.
    func testReconciliationIsIdempotent() {
        let first = ScheduleReconciliation.action(desired: noon, scheduled: nil)
        guard case .replace(let scheduled) = first else {
            return XCTFail("expected a replace, got \(first)")
        }
        XCTAssertEqual(
            ScheduleReconciliation.action(desired: noon, scheduled: scheduled),
            .noChange
        )
    }

    // MARK: - Status

    func testStatusIsNotScheduledWhenTheUserHasItOff() {
        XCTAssertEqual(
            ScheduleReconciliation.status(wanted: false, permitted: true, hasTarget: true),
            .notScheduled
        )
        // Off outranks everything else: a disabled feature is not "needs
        // permission", however the permissions happen to sit.
        XCTAssertEqual(
            ScheduleReconciliation.status(wanted: false, permitted: false, hasTarget: false),
            .notScheduled
        )
    }

    func testStatusReportsMissingPermissionAheadOfAMissingTarget() {
        XCTAssertEqual(
            ScheduleReconciliation.status(wanted: true, permitted: false, hasTarget: false),
            .needsPermission,
            "permission is the actionable one, so it is named first"
        )
    }

    /// The state the old code could not express: the toggle is on, permission
    /// is granted, and there is still nothing scheduled because no target
    /// exists yet. Settings used to just echo the toggle back.
    func testStatusDistinguishesUnavailableFromNotScheduled() {
        XCTAssertEqual(
            ScheduleReconciliation.status(wanted: true, permitted: true, hasTarget: false),
            .unavailable
        )
    }

    func testStatusIsScheduledWhenEverythingLinesUp() {
        XCTAssertEqual(
            ScheduleReconciliation.status(wanted: true, permitted: true, hasTarget: true),
            .scheduled
        )
    }

    func testOnlyMissingPermissionOffersTheUserSomethingToDo() {
        XCTAssertTrue(ScheduleStatus.needsPermission.isActionable)
        for status in ScheduleStatus.allCases where status != .needsPermission {
            XCTAssertFalse(status.isActionable, status.rawValue)
        }
    }

    func testEveryStatusHasALabel() {
        for status in ScheduleStatus.allCases {
            XCTAssertFalse(status.label.isEmpty, status.rawValue)
        }
    }
}
