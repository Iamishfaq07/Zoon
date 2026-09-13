import XCTest

/// Clock time is a circle. These pin the two places that were still treating
/// it as a line.
final class CircularTimeHardeningTests: XCTestCase {

    // MARK: - Social jetlag

    /// `SleepRegularity`'s midpoints are wall-clock hours shifted so an
    /// evening midpoint reads negative (>= 18 becomes h − 24). That keeps the
    /// median stable across midnight and makes plain subtraction unsafe:
    /// 17.9 stays 17.9 while 18.1 becomes −5.9, so `abs(a − b)` reported a
    /// twelve-minute difference as 23.8 hours.
    func testSocialJetlagAcrossTheShiftBoundary() {
        let regularity = SleepRegularity(
            index: 70, nightCount: 14, validPairCount: 13,
            weekdayMidpoint: 17.9,
            weekendMidpoint: -5.9   // 18.1, as the midpoint helper stores it
        )
        let jetlag = try XCTUnwrap(regularity.socialJetlagHours)
        XCTAssertEqual(jetlag, 0.2, accuracy: 0.001,
                       "12 minutes apart, not 23h48m")
    }

    /// The ordinary case must be unchanged by the fix.
    func testSocialJetlagOrdinaryWeekendShift() throws {
        let regularity = SleepRegularity(
            index: 70, nightCount: 14, validPairCount: 13,
            weekdayMidpoint: 2.0, weekendMidpoint: 4.0
        )
        XCTAssertEqual(try XCTUnwrap(regularity.socialJetlagHours), 2.0, accuracy: 0.001)
    }

    /// Symmetric: a distance has no direction.
    func testSocialJetlagIsSymmetric() throws {
        let forward = SleepRegularity(
            index: 70, nightCount: 14, validPairCount: 13,
            weekdayMidpoint: 23.5, weekendMidpoint: 1.5
        )
        let backward = SleepRegularity(
            index: 70, nightCount: 14, validPairCount: 13,
            weekdayMidpoint: 1.5, weekendMidpoint: 23.5
        )
        XCTAssertEqual(
            try XCTUnwrap(forward.socialJetlagHours),
            try XCTUnwrap(backward.socialJetlagHours),
            accuracy: 0.001
        )
    }

    /// The shared utility is the contract the engines depend on.
    func testCircularDistanceNeverExceedsHalfThePeriod() {
        for a in stride(from: 0.0, to: 24.0, by: 0.5) {
            for b in stride(from: 0.0, to: 24.0, by: 0.5) {
                let d = Statistics.circularDistance(a, b, period: 24)
                XCTAssertLessThanOrEqual(d, 12.0 + 1e-9)
                XCTAssertGreaterThanOrEqual(d, 0)
                XCTAssertFalse(d.isNaN)
            }
        }
    }
}
