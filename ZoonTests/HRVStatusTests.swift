import XCTest

final class HRVStatusTests: XCTestCase {

    // MARK: - HRVStatus

    func testEvaluateReturnsBuildingWithFewerThanMinimumLongTermNights() {
        let short = Array(repeating: 55.0, count: HRVStatus.minimumNights - 1)
        let status = HRVStatus.evaluate(recentHRV: [55, 56], longTermHRV: short)
        XCTAssertEqual(status.state, .building)
        XCTAssertNil(status.baseline)
    }

    func testEvaluateReturnsBuildingWithEmptyRecentHRV() {
        let long = Array(repeating: 55.0, count: HRVStatus.minimumNights)
        let status = HRVStatus.evaluate(recentHRV: [], longTermHRV: long)
        XCTAssertEqual(status.state, .building)
        XCTAssertNil(status.weeklyAverage)
    }

    func testEvaluateReadsBalancedWhenWeeklyMatchesBaseline() {
        // Constant baseline (SD = 0), weekly equal to the mean should still
        // read as balanced (falls exactly on the boundary).
        let long = Array(repeating: 50.0, count: HRVStatus.minimumNights)
        let status = HRVStatus.evaluate(recentHRV: [50, 50], longTermHRV: long)
        XCTAssertEqual(status.state, .balanced)
    }

    func testEvaluateReadsUnbalancedAboveTheUpperBound() {
        // Baseline with real variance so the bounds are non-zero, then a
        // weekly average well above the upper bound.
        let long = (0..<30).map { $0 % 2 == 0 ? 45.0 : 55.0 }
        let status = HRVStatus.evaluate(recentHRV: [90, 90], longTermHRV: long)
        XCTAssertEqual(status.state, .unbalanced)
    }

    func testEvaluateReadsLowJustBelowTheLowerBound() {
        let long = (0..<30).map { $0 % 2 == 0 ? 45.0 : 55.0 } // mean 50, sd 5
        // Just under lower bound (45) but within 2 SD (40).
        let status = HRVStatus.evaluate(recentHRV: [42, 42], longTermHRV: long)
        XCTAssertEqual(status.state, .low)
    }

    func testEvaluateReadsPoorBeyondTwoStandardDeviations() {
        let long = (0..<30).map { $0 % 2 == 0 ? 45.0 : 55.0 } // mean 50, sd 5
        let status = HRVStatus.evaluate(recentHRV: [30, 30], longTermHRV: long)
        XCTAssertEqual(status.state, .poor)
    }

    // MARK: - Chronotype

    func testInferReturnsUnknownBelowMinimumNights() {
        let short = Array(repeating: -1.0, count: Chronotype.minimumNights - 1)
        let result = Chronotype.infer(bedtimeHours: short, durations: short.map { _ in 450 }, consistencyMinutes: 10)
        XCTAssertEqual(result.kind, .unknown)
    }

    func testInferClassifiesLionForEarlyStableBedtime() {
        let bedtimes = Array(repeating: -2.0, count: Chronotype.minimumNights) // 10pm
        let durations = Array(repeating: 450.0, count: Chronotype.minimumNights)
        let result = Chronotype.infer(bedtimeHours: bedtimes, durations: durations, consistencyMinutes: 10)
        XCTAssertEqual(result.kind, .lion)
    }

    func testInferClassifiesWolfForLateStableBedtime() {
        let bedtimes = Array(repeating: 1.0, count: Chronotype.minimumNights) // 1am
        let durations = Array(repeating: 450.0, count: Chronotype.minimumNights)
        let result = Chronotype.infer(bedtimeHours: bedtimes, durations: durations, consistencyMinutes: 10)
        XCTAssertEqual(result.kind, .wolf)
    }

    func testInferClassifiesBearForTypicalBedtime() {
        let bedtimes = Array(repeating: -0.5, count: Chronotype.minimumNights) // 11:30pm
        let durations = Array(repeating: 450.0, count: Chronotype.minimumNights)
        let result = Chronotype.infer(bedtimeHours: bedtimes, durations: durations, consistencyMinutes: 10)
        XCTAssertEqual(result.kind, .bear)
    }

    func testInferClassifiesDolphinForHighSpreadEvenWithStableTimingMedian() {
        // Median bedtime alone would read as "bear," but a high spread must
        // take priority -- this ordering is explicitly documented in the
        // source (checked first so an irregular sleeper isn't misread as
        // one of the stable types).
        let bedtimes = Array(repeating: -0.5, count: Chronotype.minimumNights)
        let durations = Array(repeating: 450.0, count: Chronotype.minimumNights)
        let result = Chronotype.infer(bedtimeHours: bedtimes, durations: durations, consistencyMinutes: 90)
        XCTAssertEqual(result.kind, .dolphin)
    }

    func testInferClassifiesDolphinForShortDurationEvenWithStableTiming() {
        let bedtimes = Array(repeating: -0.5, count: Chronotype.minimumNights)
        let durations = Array(repeating: 300.0, count: Chronotype.minimumNights) // under 360
        let result = Chronotype.infer(bedtimeHours: bedtimes, durations: durations, consistencyMinutes: 10)
        XCTAssertEqual(result.kind, .dolphin)
    }

    func testFormattedBedtimeConvertsNegativeHourBackToWallClock() {
        // -0.5 -> 23:30
        let result = Chronotype(kind: .bear, medianBedtimeHour: -0.5, medianDurationMinutes: 450, consistencyMinutes: 10, nightCount: 20)
        XCTAssertEqual(result.formattedBedtime, "23:30")
    }

    func testFormattedBedtimeHandlesPositiveHour() {
        // 1.25 -> 01:15
        let result = Chronotype(kind: .wolf, medianBedtimeHour: 1.25, medianDurationMinutes: 450, consistencyMinutes: 10, nightCount: 20)
        XCTAssertEqual(result.formattedBedtime, "01:15")
    }
}
