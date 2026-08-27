import XCTest

final class ZoonTwinTests: XCTestCase {

    /// Nights where longer sleep genuinely coincides with higher HRV, plus a
    /// seeded wobble so both the split variable and the outcome have real
    /// spread rather than two flat levels.
    private func coupledNights(
        _ count: Int = 40, coupling: Double = 0.05, seed: UInt64 = 31
    ) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let asleep = 450 + generator.nextDouble(in: -90...90)
            // HRV rises with duration by `coupling` ms per minute, plus noise.
            let hrv = 55 + (asleep - 450) * coupling + generator.nextDouble(in: -3...3)
            return Fixture.night(
                daysAgo: count - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9,
                avgHRV: hrv
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - The projection

    func testLongerNightsShowTheCoupledOutcome() throws {
        let projection = try XCTUnwrap(
            ZoonTwin.project(
                nights: coupledNights(), lever: .duration, direction: .more, outcome: .hrv
            )
        )

        XCTAssertGreaterThan(projection.outcomeWithLever, projection.outcomeOtherwise)
        XCTAssertTrue(projection.isImprovement, "more HRV is the better direction")
        XCTAssertGreaterThanOrEqual(projection.leverNights, ZoonTwin.minimumGroupNights)
        XCTAssertGreaterThanOrEqual(projection.otherNights, ZoonTwin.minimumGroupNights)
    }

    func testTheLessDirectionReportsTheOppositeSide() throws {
        let nights = coupledNights()
        let more = try XCTUnwrap(
            ZoonTwin.project(nights: nights, lever: .duration, direction: .more, outcome: .hrv)
        )
        let less = try XCTUnwrap(
            ZoonTwin.project(nights: nights, lever: .duration, direction: .less, outcome: .hrv)
        )

        XCTAssertGreaterThan(more.outcomeWithLever, less.outcomeWithLever,
                             "the long-sleep group should have higher HRV than the short-sleep group")
        XCTAssertFalse(less.isImprovement)
    }

    /// An outcome with no relationship to the lever should show a small
    /// effect, not a confident one.
    func testAnUncoupledOutcomeShowsALittleEffect() throws {
        let nights = coupledNights(coupling: 0)
        let projection = try XCTUnwrap(
            ZoonTwin.project(nights: nights, lever: .duration, direction: .more, outcome: .hrv)
        )
        XCTAssertLessThan(abs(projection.delta), 4,
                          "with no coupling the two groups' HRV should barely differ")
    }

    // MARK: - Refusals

    /// Reporting that nights with more sleep have more sleep is not a finding.
    func testLeverAndOutcomeCannotBeTheSameMetric() {
        XCTAssertNil(
            ZoonTwin.project(
                nights: coupledNights(), lever: .duration, direction: .more, outcome: .duration
            )
        )
    }

    func testTooFewNightsReturnsNil() {
        XCTAssertNil(
            ZoonTwin.project(
                nights: coupledNights(8), lever: .duration, direction: .more, outcome: .hrv
            )
        )
    }

    /// A lever with no spread cannot split anything: every night sits at the
    /// median, so one side of the comparison would be empty.
    func testALeverWithNoSpreadReturnsNil() {
        var generator = SeededGenerator(seed: 4)
        let flat = (0..<40).map { index in
            Fixture.night(
                daysAgo: 40 - index,
                timeAsleepMinutes: 450,
                timeInBedMinutes: 500,
                avgHRV: 55 + generator.nextDouble(in: -3...3)
            )
        }.sorted { $0.date < $1.date }

        XCTAssertNil(
            ZoonTwin.project(nights: flat, lever: .duration, direction: .more, outcome: .hrv)
        )
    }

    /// A night missing either value is dropped from both sides, so the two
    /// groups are always drawn from the same population.
    func testNightsMissingTheOutcomeAreExcludedEntirely() throws {
        // 60 rather than 40 so both groups clear the minimum comfortably once
        // a third of the nights are dropped for missing the outcome.
        var withHoles = coupledNights(60)
        // Blank the outcome on a run of nights.
        withHoles = withHoles.enumerated().map { index, night in
            index % 3 == 0
                ? Fixture.night(
                    daysAgo: withHoles.count - index,
                    timeAsleepMinutes: night.timeAsleepMinutes,
                    timeInBedMinutes: night.timeInBedMinutes,
                    avgHRV: nil
                )
                : night
        }

        let projection = try XCTUnwrap(
            ZoonTwin.project(nights: withHoles, lever: .duration, direction: .more, outcome: .hrv)
        )
        XCTAssertLessThan(
            projection.leverNights + projection.otherNights, withHoles.count,
            "nights without the outcome must not be counted"
        )
    }

    // MARK: - Confidence

    /// A comparison is only as good as its thinner side.
    func testConfidenceComesFromTheSmallerGroup() throws {
        let projection = try XCTUnwrap(
            ZoonTwin.project(
                nights: coupledNights(80), lever: .duration, direction: .more, outcome: .hrv
            )
        )
        XCTAssertNotEqual(projection.confidence, .insufficient)
    }

    // MARK: - projectAll

    func testProjectAllExcludesTheLeverItself() {
        let projections = ZoonTwin.projectAll(
            nights: coupledNights(), lever: .duration, direction: .more
        )
        XCTAssertFalse(projections.contains { $0.outcome == .duration })
    }

    func testProjectAllSortsStrongestEffectFirst() {
        let projections = ZoonTwin.projectAll(
            nights: coupledNights(), lever: .duration, direction: .more
        )
        let effects = projections.map { abs($0.delta) / max(abs($0.outcomeOtherwise), 1) }
        XCTAssertEqual(effects, effects.sorted(by: >))
    }

    // MARK: - Copy

    func testSentenceNamesBothGroupSizes() throws {
        let projection = try XCTUnwrap(
            ZoonTwin.project(
                nights: coupledNights(), lever: .duration, direction: .more, outcome: .hrv
            )
        )

        XCTAssertTrue(projection.sentence.contains("\(projection.leverNights) nights"), projection.sentence)
        XCTAssertTrue(projection.sentence.contains("\(projection.otherNights)"), projection.sentence)
    }

    /// This splits on one variable and matches on nothing. The copy must not
    /// imply a controlled comparison or a prediction.
    func testCaveatRefusesPredictionAndProof() throws {
        let projection = try XCTUnwrap(
            ZoonTwin.project(
                nights: coupledNights(), lever: .duration, direction: .more, outcome: .hrv
            )
        )
        let caveat = projection.caveat.lowercased()

        XCTAssertTrue(caveat.contains("not a prediction"), projection.caveat)
        XCTAssertTrue(caveat.contains("not proof"), projection.caveat)
        XCTAssertTrue(caveat.contains("differ in other ways"), projection.caveat)
        XCTAssertFalse(caveat.contains("because"), projection.caveat)
    }
}
