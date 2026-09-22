import XCTest

final class LateWorkoutTimingCurveTests: XCTestCase {

    func testTooFewNightsProducesNoCurve() {
        let nights = (0..<6).map { i in
            Fixture.night(daysAgo: i, timeAsleepMinutes: 420, lastWorkoutHoursBeforeBed: i < 3 ? 1.0 : 5.0)
        }
        XCTAssertNil(LateWorkoutTimingCurve.learn(nights: nights))
    }

    func testLateWorkoutsAssociatedWithShorterSleepAreDescribedObservationally() throws {
        var nights: [SleepNightFeatures] = []
        for i in 0..<6 {
            nights.append(Fixture.night(daysAgo: i, timeAsleepMinutes: 390, lastWorkoutHoursBeforeBed: 1.5))
        }
        for i in 6..<12 {
            nights.append(Fixture.night(daysAgo: i, timeAsleepMinutes: 450, lastWorkoutHoursBeforeBed: 5.0))
        }
        let finding = try XCTUnwrap(LateWorkoutTimingCurve.learn(nights: nights))
        XCTAssertEqual(finding.lateCount, 6)
        XCTAssertEqual(finding.earlierCount, 6)
        XCTAssertTrue(finding.sentence.lowercased().contains("associated"))
        XCTAssertFalse(finding.sentence.lowercased().contains("cause"))
        XCTAssertTrue(finding.limitation.lowercased().contains("not proof"))
        XCTAssertGreaterThanOrEqual(finding.sampleCount, 12)
    }

    func testLittleDifferenceIsNotAUniversalRule() throws {
        var nights: [SleepNightFeatures] = []
        for i in 0..<5 {
            nights.append(Fixture.night(daysAgo: i, timeAsleepMinutes: 440, lastWorkoutHoursBeforeBed: 1.0))
        }
        for i in 5..<10 {
            nights.append(Fixture.night(daysAgo: i, timeAsleepMinutes: 445, lastWorkoutHoursBeforeBed: 6.0))
        }
        let finding = try XCTUnwrap(LateWorkoutTimingCurve.learn(nights: nights))
        XCTAssertTrue(finding.sentence.lowercased().contains("not shown a meaningful"))
    }

    func testNightsWithoutWorkoutTimingAreSkippedNotZero() throws {
        var nights: [SleepNightFeatures] = []
        for i in 0..<5 {
            nights.append(Fixture.night(daysAgo: i, timeAsleepMinutes: 400, lastWorkoutHoursBeforeBed: 1.0))
        }
        for i in 5..<10 {
            nights.append(Fixture.night(daysAgo: i, timeAsleepMinutes: 460, lastWorkoutHoursBeforeBed: 4.5))
        }
        nights.append(Fixture.night(daysAgo: 11, timeAsleepMinutes: 200, lastWorkoutHoursBeforeBed: nil))
        let finding = try XCTUnwrap(LateWorkoutTimingCurve.learn(nights: nights))
        XCTAssertEqual(finding.lateCount, 5)
        XCTAssertEqual(finding.earlierCount, 5)
    }
}
