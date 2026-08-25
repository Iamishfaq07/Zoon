import XCTest

final class TonightTimelineCardTests: XCTestCase {

    private func date(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return calendar.date(byAdding: .day, value: dayOffset, to: base) ?? base
    }

    /// The general-guideline cutoff is bedtime minus
    /// `BedtimeReminder.caffeineCutoffLeadHours` -- an 11pm bedtime should
    /// land at 3pm the same day.
    func testCutoffIsEightHoursBeforeBedtime() {
        let bedtime = date(23, 0)
        let now = date(9, 0) // well before the cutoff -- not stale yet

        let cutoff = TonightTimelineCard.caffeineCutoff(bedtime: bedtime, now: now)

        XCTAssertEqual(cutoff, date(15, 0))
    }

    /// Still shown a little while after it's passed -- someone checking
    /// Today mid-afternoon should still see it.
    func testCutoffStillShownShortlyAfterItPasses() {
        let bedtime = date(23, 0) // cutoff at 3pm
        let now = date(16, 0) // 1 hour after cutoff

        XCTAssertNotNil(TonightTimelineCard.caffeineCutoff(bedtime: bedtime, now: now))
    }

    /// Hidden once well past -- by evening, a 3pm cutoff has nothing left to
    /// tell someone.
    func testCutoffHiddenOnceWellPast() {
        let bedtime = date(23, 0) // cutoff at 3pm
        let now = date(20, 0) // 5 hours after cutoff

        XCTAssertNil(TonightTimelineCard.caffeineCutoff(bedtime: bedtime, now: now))
    }
}
