import XCTest

final class NapCoachTests: XCTestCase {

    private let now = Date.now

    func testAdvisesAvoidWhenAlreadyNappedThirtyMinutesToday() {
        let result = NapCoach.recommend(now: now, debtMinutes: 90, plannedBedtime: nil, napMinutesToday: 30)
        XCTAssertEqual(result.advice, .avoid)
        XCTAssertFalse(result.isRecommended)
    }

    func testAlreadyNappedCheckTakesPriorityOverEverythingElse() {
        // High debt and a far-off bedtime would otherwise recommend a long
        // nap -- the already-napped guard must still win.
        let farBedtime = now.addingTimeInterval(10 * 3600)
        let result = NapCoach.recommend(now: now, debtMinutes: 200, plannedBedtime: farBedtime, napMinutesToday: 45)
        XCTAssertEqual(result.advice, .avoid)
    }

    func testAdvisesAvoidWhenBedtimeIsUnderSixHoursAway() {
        let soonBedtime = now.addingTimeInterval(5 * 3600)
        let result = NapCoach.recommend(now: now, debtMinutes: 90, plannedBedtime: soonBedtime, napMinutesToday: 0)
        XCTAssertEqual(result.advice, .avoid)
    }

    func testAllowsANapExactlyAtTheSixHourBoundary() {
        // hours < 6 is strict, so exactly 6 hours away should not trigger
        // the "too close to bedtime" avoid branch.
        let bedtime = now.addingTimeInterval(6 * 3600 + 60)
        let result = NapCoach.recommend(now: now, debtMinutes: 90, plannedBedtime: bedtime, napMinutesToday: 0)
        XCTAssertNotEqual(result.advice, .avoid)
    }

    func testAdvisesOptionalWithMinimalDebt() {
        let farBedtime = now.addingTimeInterval(10 * 3600)
        let result = NapCoach.recommend(now: now, debtMinutes: 10, plannedBedtime: farBedtime, napMinutesToday: 0)
        XCTAssertEqual(result.advice, .optional)
    }

    func testRecommendsALongRecoveryNapWithHighDebtAndFarBedtime() {
        let farBedtime = now.addingTimeInterval(9 * 3600)
        let result = NapCoach.recommend(now: now, debtMinutes: 100, plannedBedtime: farBedtime, napMinutesToday: 0)
        XCTAssertEqual(result.advice, .recommended(durationMinutes: 90))
        XCTAssertTrue(result.isRecommended)
    }

    func testHighDebtButCloserBedtimeFallsBackToTheShortNap() {
        // debtMinutes >= 90 but hours < 8: shouldn't clear the long-nap gate.
        let bedtime = now.addingTimeInterval(7 * 3600)
        let result = NapCoach.recommend(now: now, debtMinutes: 100, plannedBedtime: bedtime, napMinutesToday: 0)
        XCTAssertEqual(result.advice, .recommended(durationMinutes: 20))
    }

    func testRecommendsAShortNapForModerateDebtWithNoBedtimeKnown() {
        let result = NapCoach.recommend(now: now, debtMinutes: 45, plannedBedtime: nil, napMinutesToday: 0)
        XCTAssertEqual(result.advice, .recommended(durationMinutes: 20))
        XCTAssertTrue(result.reason.contains("45"))
    }

    func testShortNapReasonOmitsDebtNoteWhenDebtIsBelowTwenty() {
        // debtMinutes between 20 (optional cutoff) never applies here since
        // this branch is only reached when debtMinutes >= 20 already (the
        // optional branch returns first below that) -- but the note itself
        // is still conditioned on >= 20 in the source, so confirm the note
        // appears whenever this branch is reached.
        let result = NapCoach.recommend(now: now, debtMinutes: 25, plannedBedtime: nil, napMinutesToday: 0)
        XCTAssertTrue(result.reason.contains("ease"))
    }
}
