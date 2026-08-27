import XCTest

final class SleepMapTests: XCTestCase {

    /// A balanced 3x3 of nights: three duration levels crossed with three
    /// resting-heart-rate levels, jittered so the tercile cuts fall cleanly
    /// between the clusters rather than landing on a repeated value.
    ///
    /// `standoutRegion` gets a visibly better HRV than every other cell, so
    /// the winner is known in advance rather than read back off the result.
    private func gridNights(
        perCell: Int = 5,
        standoutRegion: (x: Int, y: Int) = (0, 2),
        seed: UInt64 = 17
    ) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        var nights: [SleepNightFeatures] = []
        var day = 0
        for (xIndex, asleep) in [360.0, 450.0, 540.0].enumerated() {
            for (yIndex, rhr) in [48.0, 54.0, 60.0].enumerated() {
                for _ in 0..<perCell {
                    day += 1
                    let duration = asleep + generator.nextDouble(in: -12...12)
                    let heartRate = rhr + generator.nextDouble(in: -2...2)
                    let isStandout = xIndex == standoutRegion.x && yIndex == standoutRegion.y
                    nights.append(Fixture.night(
                        daysAgo: day,
                        timeAsleepMinutes: duration,
                        timeInBedMinutes: duration / 0.9,
                        avgHRV: (isStandout ? 70 : 52) + generator.nextDouble(in: -1...1),
                        restingHeartRate: heartRate
                    ))
                }
            }
        }
        return nights.sorted { $0.date < $1.date }
    }

    /// Nights where resting heart rate tracks duration closely, so the
    /// off-diagonal regions are nearly empty. Region night counts come out
    /// 14/2/0, 2/11/3, 0/3/13 -- a realistic shape, and one where raising
    /// the density floor isolates a known number of scored regions.
    private func lopsidedNights(seed: UInt64 = 29) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<48).map { index in
            // The first 26 nights cluster tightly, the rest spread wide, so
            // one diagonal region ends up much denser than the others.
            let duration = 450 + (index < 26
                ? generator.nextDouble(in: -10...10)
                : generator.nextDouble(in: -130...130))
            let heartRate = 54 + (duration - 450) * 0.06 + generator.nextDouble(in: -1...1)
            return Fixture.night(
                daysAgo: 48 - index,
                timeAsleepMinutes: duration,
                timeInBedMinutes: duration / 0.9,
                avgHRV: 52 + generator.nextDouble(in: -1...1),
                restingHeartRate: heartRate
            )
        }.sorted { $0.date < $1.date }
    }

    private func buildGrid(
        _ nights: [SleepNightFeatures]? = nil,
        minimumRegionNights: Int = SleepMap.minimumRegionNights
    ) throws -> SleepMap.Map {
        try XCTUnwrap(SleepMap.build(
            nights: nights ?? gridNights(),
            xAxis: .duration, yAxis: .restingHeartRate, outcome: .hrv,
            minimumRegionNights: minimumRegionNights
        ))
    }

    // MARK: - The grid

    func testEveryRegionIsReturnedIncludingTheEmptyOnes() throws {
        let map = try buildGrid(lopsidedNights())
        XCTAssertEqual(map.regions.count, 9)
        XCTAssertTrue(map.regions.contains { $0.nightCount == 0 },
                      "the gaps in where someone sleeps are part of the map")
    }

    func testRegionCountsAccountForEveryUsableNight() throws {
        let map = try buildGrid()
        XCTAssertEqual(map.regions.reduce(0) { $0 + $1.nightCount }, map.totalNights)
    }

    func testRegionIdsAreUnique() throws {
        let map = try buildGrid()
        XCTAssertEqual(Set(map.regions.map(\.id)).count, 9)
    }

    // MARK: - Best region

    func testTheBestRegionIsTheOneWithTheBestOutcome() throws {
        let map = try buildGrid()
        let best = try XCTUnwrap(map.best)

        XCTAssertEqual(best.x, .low, "the standout cell sits in the shortest-duration band")
        XCTAssertEqual(best.y, .high)
        XCTAssertEqual(try XCTUnwrap(best.medianOutcome), 70, accuracy: 2)
    }

    /// The same history read against a lower-is-better outcome must not pick
    /// the winner by habit.
    func testALowerIsBetterOutcomeTakesTheMinimum() throws {
        let nights = gridNights()
        let higher = try XCTUnwrap(SleepMap.build(
            nights: nights, xAxis: .duration, yAxis: .restingHeartRate, outcome: .hrv
        ))
        let lower = try XCTUnwrap(SleepMap.build(
            nights: nights, xAxis: .duration, yAxis: .hrv, outcome: .restingHeartRate
        ))

        XCTAssertEqual(
            try XCTUnwrap(higher.best?.medianOutcome),
            try XCTUnwrap(higher.scoredRegions.compactMap(\.medianOutcome).max()),
            "HRV is better high, so the winner is the maximum"
        )
        XCTAssertEqual(
            try XCTUnwrap(lower.best?.medianOutcome),
            try XCTUnwrap(lower.scoredRegions.compactMap(\.medianOutcome).min()),
            "resting heart rate is better low, so the winner is the minimum"
        )
    }

    /// A region too thin to score can never win, however good the two nights
    /// in it happened to be.
    func testAThinRegionIsDrawnButNeverScoredOrRanked() throws {
        let map = try buildGrid(lopsidedNights())
        let thin = map.regions.filter { (1..<SleepMap.minimumRegionNights).contains($0.nightCount) }

        XCTAssertFalse(thin.isEmpty, "precondition: some regions hold one or two nights")
        XCTAssertTrue(thin.allSatisfy { !$0.isScored })
        XCTAssertFalse(map.scoredRegions.contains { thin.map(\.id).contains($0.id) })
    }

    /// One region beating nothing is not a comparison.
    func testASingleScoredRegionYieldsNoBest() throws {
        // At this floor exactly one region -- the 14-night one -- still
        // scores; everything else falls below it.
        let map = try buildGrid(lopsidedNights(), minimumRegionNights: 14)

        XCTAssertEqual(map.scoredRegions.count, 1, "precondition for this test")
        XCTAssertNil(map.best)
        XCTAssertTrue(map.sentence.contains("Not enough nights"), map.sentence)
    }

    // MARK: - Usual region

    func testUsualIsTheDensestRegion() throws {
        let map = try buildGrid(lopsidedNights())
        XCTAssertEqual(map.usual.nightCount, map.regions.map(\.nightCount).max())
    }

    /// Worth saying plainly rather than dressing an unchanged pattern up as a
    /// discovery.
    func testBestIsAlreadyUsualIsReportedWhenTheyCoincide() throws {
        let map = try buildGrid(gridNights(standoutRegion: (0, 0)))

        XCTAssertTrue(map.bestIsAlreadyUsual)
        XCTAssertTrue(map.sentence.contains("already where most of your nights sit"), map.sentence)
    }

    func testBestIsNotAlreadyUsualWhenTheyDiffer() throws {
        let map = try buildGrid()
        XCTAssertFalse(map.bestIsAlreadyUsual)
        XCTAssertFalse(map.sentence.contains("already where"), map.sentence)
    }

    // MARK: - Refusals

    func testTooFewNightsReturnsNil() {
        XCTAssertNil(SleepMap.build(
            nights: Array(gridNights().prefix(20)),
            xAxis: .duration, yAxis: .restingHeartRate, outcome: .hrv
        ))
    }

    /// An axis where a third of the nights share one value cannot be cut into
    /// thirds, and a 2x3 grid must not be presented as a 3x3.
    func testAnAxisWithNoSpreadReturnsNil() {
        var generator = SeededGenerator(seed: 7)
        let flat = (0..<45).map { index in
            Fixture.night(
                daysAgo: 45 - index,
                timeAsleepMinutes: 450,
                timeInBedMinutes: 500,
                avgHRV: 55 + generator.nextDouble(in: -5...5),
                restingHeartRate: 54 + generator.nextDouble(in: -4...4)
            )
        }
        XCTAssertNil(SleepMap.build(
            nights: flat, xAxis: .duration, yAxis: .restingHeartRate, outcome: .hrv
        ))
    }

    /// Mapping a metric against itself reports only that it equals itself.
    func testTheThreeMetricsMustBeDistinct() {
        let nights = gridNights()
        XCTAssertNil(SleepMap.build(
            nights: nights, xAxis: .duration, yAxis: .duration, outcome: .hrv))
        XCTAssertNil(SleepMap.build(
            nights: nights, xAxis: .duration, yAxis: .hrv, outcome: .hrv))
        XCTAssertNil(SleepMap.build(
            nights: nights, xAxis: .hrv, yAxis: .restingHeartRate, outcome: .hrv))
    }

    /// A night missing any of the three values is excluded outright. Counting
    /// it in a region while leaving it out of that region's median would make
    /// the region look denser than the number it reports.
    func testNightsMissingAnyOfTheThreeValuesAreExcluded() throws {
        let complete = gridNights()
        let holed = complete.enumerated().map { index, night in
            index % 4 == 0
                ? Fixture.night(
                    daysAgo: complete.count - index,
                    timeAsleepMinutes: night.timeAsleepMinutes,
                    timeInBedMinutes: night.timeInBedMinutes,
                    avgHRV: nil,
                    restingHeartRate: night.restingHeartRate
                )
                : night
        }

        let map = try buildGrid(holed)
        XCTAssertLessThan(map.totalNights, holed.count)
        XCTAssertEqual(map.regions.reduce(0) { $0 + $1.nightCount }, map.totalNights)
    }

    // MARK: - Confidence

    /// A region that outscored one other region has not been shown to be the
    /// best of nine, however many nights are behind it.
    func testConfidenceIsCappedWhenFewRegionsScore() throws {
        let map = try buildGrid(lopsidedNights(), minimumRegionNights: 12)
        let best = try XCTUnwrap(map.best)

        XCTAssertEqual(map.scoredRegions.count, 2, "precondition for this test")
        XCTAssertGreaterThanOrEqual(best.nightCount, 8,
                                    "precondition: the winner is deep enough to rate higher on its own")
        XCTAssertEqual(map.confidence, .low, "breadth should cap what depth alone would allow")
    }

    func testConfidenceOrderingIsWeakestFirst() {
        XCTAssertLessThan(MetricConfidence.insufficient, .low)
        XCTAssertLessThan(MetricConfidence.low, .moderate)
        XCTAssertLessThan(MetricConfidence.moderate, .high)
    }

    // MARK: - Copy

    /// "Earlier" and "shorter" are not interchangeable, and neither is a
    /// generic "lower" for either of them.
    func testBandWordingSuitsItsAxis() {
        XCTAssertEqual(SleepMap.Band.low.phrase(for: .bedtime), "earlier")
        XCTAssertEqual(SleepMap.Band.high.phrase(for: .bedtime), "later")
        XCTAssertEqual(SleepMap.Band.low.phrase(for: .duration), "shorter")
        XCTAssertEqual(SleepMap.Band.high.phrase(for: .duration), "longer")
        XCTAssertEqual(SleepMap.Band.low.phrase(for: .hrv), "lower")
        for metric in TrendEngine.Metric.allCases {
            XCTAssertEqual(SleepMap.Band.middle.phrase(for: metric), "usual",
                           "the middle band is their middle third, not a target")
        }
    }

    func testTheSentenceNamesBothAxesAndTheNightCount() throws {
        let map = try buildGrid()
        let best = try XCTUnwrap(map.best)

        XCTAssertTrue(map.sentence.contains("sleep duration"), map.sentence)
        XCTAssertTrue(map.sentence.contains("resting heart rate"), map.sentence)
        XCTAssertTrue(map.sentence.contains("\(best.nightCount) nights"), map.sentence)
    }

    /// A region their good nights happen to sit in is not an instruction to
    /// move there.
    func testTheCaveatRefusesToPrescribe() throws {
        let caveat = try buildGrid().caveat.lowercased()

        XCTAssertTrue(caveat.contains("not a target"), caveat)
        XCTAssertTrue(caveat.contains("already had"), caveat)
        XCTAssertFalse(caveat.contains("should"), caveat)
        XCTAssertFalse(caveat.contains("because"), caveat)
    }
}
