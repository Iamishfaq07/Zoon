import XCTest

final class StatisticsTests: XCTestCase {

    func testMedianOddCount() {
        XCTAssertEqual(Statistics.median([3, 1, 2]), 2)
    }

    func testMedianEvenCount() {
        XCTAssertEqual(Statistics.median([1, 2, 3, 4]), 2.5)
    }

    func testMedianEmpty() {
        XCTAssertNil(Statistics.median([]))
    }

    func testMedianAbsoluteDeviation() {
        // Median 5; deviations |1-5|,|3-5|,|5-5|,|7-5|,|9-5| = 4,2,0,2,4 -> median 2.
        XCTAssertEqual(Statistics.medianAbsoluteDeviation([1, 3, 5, 7, 9]), 2)
    }

    func testRobustZUsesMADWhenNonDegenerate() {
        let history = [50.0, 52, 48, 55, 45, 51, 49]
        // Median of history is 50; a value far outside should score a
        // strongly negative or positive z depending on direction.
        let z = Statistics.robustZ(30, in: history)
        XCTAssertNotNil(z)
        XCTAssertLessThan(z!, -2, "A value far below a tight history should read as a strongly negative z")
    }

    /// The exact scenario `robustZ`'s doc comment describes: a metric that's
    /// been nearly identical every night (MAD ~ 0) must not turn a tiny
    /// wobble into an enormous, meaningless z-score by dividing by ~zero.
    func testRobustZFallsBackWhenMADIsDegenerate() {
        let history = Array(repeating: 50.0, count: 10)
        let z = Statistics.robustZ(50.5, in: history)
        // IQR is also 0 here, and so is SD (constant series) -- every
        // fallback is degenerate, so this must come back nil, never a huge
        // spurious number.
        XCTAssertNil(z)
    }

    func testRobustZRequiresMinimumSampleSize() {
        XCTAssertNil(Statistics.robustZ(10, in: [1, 2]))
    }

    func testInterpolateClampsBelowRange() {
        let anchors: [(x: Double, y: Double)] = [(0, 10), (10, 100)]
        XCTAssertEqual(Statistics.interpolate(-5, anchors: anchors), 10)
    }

    func testInterpolateClampsAboveRange() {
        let anchors: [(x: Double, y: Double)] = [(0, 10), (10, 100)]
        XCTAssertEqual(Statistics.interpolate(15, anchors: anchors), 100)
    }

    func testInterpolateMidpoint() {
        let anchors: [(x: Double, y: Double)] = [(0, 0), (10, 100)]
        XCTAssertEqual(Statistics.interpolate(5, anchors: anchors), 50)
    }

    /// The convention every circadian calculation in the app shares: evening
    /// clock times plot as negative minutes-from-midnight, so 23:50 and
    /// 00:10 -- twenty real minutes apart -- come out twenty apart here too,
    /// not roughly a full day apart the way naive minutes-since-midnight
    /// would put them.
    func testCircularMinutesFromMidnightKeepsLateNightAndEarlyMorningClose() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 50))!
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 10))!

        let lateMinutes = Statistics.circularMinutesFromMidnight(lateNight, calendar: calendar)
        let earlyMinutes = Statistics.circularMinutesFromMidnight(earlyMorning, calendar: calendar)

        XCTAssertEqual(abs(earlyMinutes - lateMinutes), 20, accuracy: 0.01)
    }
}
