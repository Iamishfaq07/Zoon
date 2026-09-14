import XCTest

/// An era is a claim about a stretch of someone's life. One night is not one.
final class SleepErasPersistenceTests: XCTestCase {

    /// Nights ending at `daysAgo`, counting back, with a given bedtime hour
    /// and duration. Built oldest-first so the returned array reads like
    /// history.
    private func run(
        count: Int,
        endingDaysAgo: Int,
        bedtimeHour: Int,
        minutes: Double = 450
    ) -> [SleepNightFeatures] {
        (0..<count).map { offset in
            Fixture.night(
                daysAgo: endingDaysAgo + (count - 1 - offset),
                timeAsleepMinutes: minutes,
                bedtimeHour: bedtimeHour
            )
        }
    }

    /// The reported case: thirty ordinary nights, one red-eye, then normal
    /// sleep again. That is one era with a bad night in it.
    func testSingleOutlierDoesNotCreateAnEra() {
        let nights = run(count: 30, endingDaysAgo: 11, bedtimeHour: 23)
            + run(count: 1, endingDaysAgo: 10, bedtimeHour: 3, minutes: 300)
            + run(count: 10, endingDaysAgo: 0, bedtimeHour: 23)

        XCTAssertEqual(SleepEras.detect(in: nights).count, 1)
    }

    /// Two shifted nights is still noise by the same reasoning.
    func testTwoNightDisruptionIsAbsorbed() {
        let nights = run(count: 30, endingDaysAgo: 12, bedtimeHour: 23)
            + run(count: 2, endingDaysAgo: 10, bedtimeHour: 3, minutes: 300)
            + run(count: 10, endingDaysAgo: 0, bedtimeHour: 23)

        XCTAssertEqual(SleepEras.detect(in: nights).count, 1)
    }

    /// Three sustained nights is a change, which is the point of the rule.
    func testThreeSustainedNightsBecomeAnEra() {
        let nights = run(count: 30, endingDaysAgo: 10, bedtimeHour: 23)
            + run(count: 10, endingDaysAgo: 0, bedtimeHour: 2)

        XCTAssertEqual(SleepEras.detect(in: nights).count, 2)
    }

    /// A permanent schedule move splits history once, not repeatedly.
    func testPermanentShiftSplitsOnce() {
        let nights = run(count: 20, endingDaysAgo: 20, bedtimeHour: 23)
            + run(count: 20, endingDaysAgo: 0, bedtimeHour: 10)

        XCTAssertEqual(SleepEras.detect(in: nights).count, 2)
    }

    /// A week away reads as a short era between two similar ones. Not
    /// labelled "temporary": that would be a guess about what happens next.
    func testTravelStretchReadsAsItsOwnEra() {
        let nights = run(count: 20, endingDaysAgo: 25, bedtimeHour: 23)
            + run(count: 5, endingDaysAgo: 20, bedtimeHour: 3, minutes: 540)
            + run(count: 20, endingDaysAgo: 0, bedtimeHour: 23)

        XCTAssertEqual(SleepEras.detect(in: nights).count, 3)
    }

    /// Drift of a few minutes a night never crosses the threshold, so it
    /// stays one era rather than fragmenting into many.
    func testGradualDriftDoesNotFragment() {
        let nights = (0..<40).map { offset in
            Fixture.night(
                daysAgo: 39 - offset,
                timeAsleepMinutes: 450,
                bedtimeHour: 23,
                bedtimeMinuteOffset: -offset * 4
            )
        }
        XCTAssertLessThanOrEqual(SleepEras.detect(in: nights).count, 2)
    }

    func testTooLittleHistoryReportsNothing() {
        XCTAssertTrue(SleepEras.detect(in: run(count: 5, endingDaysAgo: 0, bedtimeHour: 23)).isEmpty)
    }

    /// Every era reports a real span and no NaN.
    func testErasHaveSaneInvariants() {
        let nights = run(count: 20, endingDaysAgo: 20, bedtimeHour: 23)
            + run(count: 20, endingDaysAgo: 0, bedtimeHour: 10)

        for era in SleepEras.detect(in: nights) {
            XCTAssertGreaterThan(era.nights, 0)
            XCTAssertLessThanOrEqual(era.start, era.end)
            XCTAssertFalse(era.averageSleepMinutes.isNaN)
            XCTAssertGreaterThan(era.averageSleepMinutes, 0)
        }
    }
}
