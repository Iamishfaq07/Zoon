import XCTest

/// Tonight states what is really set, and never an old entry as active.
final class ReminderScheduleStatusTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func line(_ status: ScheduleStatus, at date: Date?, _ delivery: ScheduleReconciliation.Delivery = .notification) -> String? {
        ScheduleReconciliation.statusLine(
            label: "Bedtime reminder", delivery: delivery, status: status,
            scheduledFor: date, now: now, timeText: { _ in "10:30" }
        )
    }

    func testAScheduledItemNamesItsKindAndTime() {
        XCTAssertEqual(line(.scheduled, at: now.addingTimeInterval(3600)), "Bedtime reminder (notification): 10:30")
        XCTAssertEqual(line(.scheduled, at: now.addingTimeInterval(3600), .alarm), "Bedtime reminder (alarm): 10:30")
    }

    /// An entry for a night that is over is not shown as set.
    func testAPassedTimeIsNotShownAsScheduled() {
        let text = line(.scheduled, at: now.addingTimeInterval(-60))
        XCTAssertEqual(text, "Bedtime reminder: not set for tonight yet")
    }

    func testFailuresAndPermissionAreStated() {
        XCTAssertEqual(line(.failed, at: nil), "Bedtime reminder: could not be set")
        XCTAssertEqual(line(.needsPermission, at: nil), "Bedtime reminder: needs permission")
        XCTAssertNil(line(.notScheduled, at: nil))
    }
}
