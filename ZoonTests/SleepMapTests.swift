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

        // Compared on the shrunk value rather than the raw median, because
        // that is what is now ranked. Taking the raw extremum was the old
        // behaviour this release exists to fix: it lets a four-night cell
        // that got lucky beat a twenty-night pattern.
        XCTAssertEqual(
            try XCTUnwrap(higher.best?.shrunkOutcome),
            try XCTUnwrap(higher.scoredRegions.compactMap(\.shrunkOutcome).max()),
            "HRV is better high, so the winner is the maximum"
        )
        XCTAssertEqual(
            try XCTUnwrap(lower.best?.shrunkOutcome),
            try XCTUnwrap(lower.scoredRegions.compactMap(\.shrunkOutcome).min()),
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

    // MARK: - Winner-selection noise

    /// The whole point of shrinkage. A thin region that got lucky must not
    /// beat a deep region that did not: with four nights, the cell that wins
    /// on a raw median is usually the cell that got the best draw, and it
    /// will be a different cell next week.
    func testShrinkagePullsAThinRegionTowardTheMiddle() {
        let overall = 50.0
        let thin = SleepMap.shrink(70, nightCount: 4, toward: overall)
        let deep = SleepMap.shrink(70, nightCount: 40, toward: overall)

        XCTAssertLessThan(thin, deep, "the thinner region should keep less of its own signal")
        XCTAssertGreaterThan(thin, overall, "shrinkage pulls toward the middle, it does not erase")
        XCTAssertLessThan(thin, 70)
    }

    func testShrinkageKeepsTheStatedFractionOfARegionsOwnSignal() {
        // n / (n + k) with k = 8: four nights keep a third.
        XCTAssertEqual(
            SleepMap.shrink(80, nightCount: 4, toward: 20),
            20 + (80 - 20) * (4 / (4 + SleepMap.shrinkageNights)),
            accuracy: 0.0001
        )
    }

    func testARegionAlreadyAtTheMiddleIsUnmoved() {
        XCTAssertEqual(SleepMap.shrink(50, nightCount: 4, toward: 50), 50, accuracy: 0.0001)
    }

    /// A region with enough nights to score carries an interval, so the map
    /// can say how sure it is rather than only what it found.
    func testScoredRegionsCarryABootstrapInterval() throws {
        let map = try buildGrid()
        for region in map.scoredRegions {
            let interval = try XCTUnwrap(region.interval, "\(region.id) scored but has no interval")
            let median = try XCTUnwrap(region.medianOutcome)
            XCTAssertLessThanOrEqual(interval.lower, median)
            XCTAssertGreaterThanOrEqual(interval.upper, median)
        }
    }

    func testAThinRegionCarriesNoInterval() throws {
        let map = try buildGrid(lopsidedNights())
        let thin = map.regions.filter { !$0.isScored }
        XCTAssertTrue(thin.allSatisfy { $0.interval == nil })
    }

    // MARK: - Overlap

    func testTwoIdenticalIntervalsOverlapCompletely() {
        let a = SleepMap.Interval(lower: 10, upper: 20)
        XCTAssertEqual(a.overlap(with: a), 1, accuracy: 0.0001)
    }

    func testDisjointIntervalsDoNotOverlap() {
        let a = SleepMap.Interval(lower: 10, upper: 20)
        let b = SleepMap.Interval(lower: 30, upper: 40)
        XCTAssertEqual(a.overlap(with: b), 0)
        XCTAssertEqual(b.overlap(with: a), 0)
    }

    /// Measured against the *narrower* interval: a wide interval that
    /// swallows a narrow one whole has not distinguished anything, however
    /// small the shared fraction of the wide one looks.
    func testOverlapIsMeasuredAgainstTheNarrowerInterval() {
        let wide = SleepMap.Interval(lower: 0, upper: 100)
        let narrow = SleepMap.Interval(lower: 40, upper: 50)
        XCTAssertEqual(wide.overlap(with: narrow), 1, accuracy: 0.0001)
    }

    /// Two point estimates that coincide overlap completely. Dividing by a
    /// zero width would read as *no* overlap, the opposite of the truth.
    func testCoincidingPointEstimatesOverlapCompletely() {
        let a = SleepMap.Interval(lower: 5, upper: 5)
        XCTAssertEqual(a.overlap(with: SleepMap.Interval(lower: 4, upper: 6)), 1, accuracy: 0.0001)
    }

    // MARK: - When the map refuses a headline

    /// A clear winner is still called a winner.
    func testAClearlySeparatedWinnerKeepsItsHeadline() throws {
        let map = try buildGrid()
        XCTAssertTrue(map.headlineIsSupported, map.sentence)
        XCTAssertTrue(map.sentence.contains("Your best"), map.sentence)
    }

    /// The spec's own distinction: "this is your ideal zone" from four
    /// nights is a claim; "your stronger nights cluster here" is an
    /// observation.
    func testOverlappingRegionsGetTheSofterSentence() throws {
        // Every cell drawn from the same distribution, so no region is
        // genuinely better than another.
        var generator = SeededGenerator(seed: 5)
        var nights: [SleepNightFeatures] = []
        var day = 0
        for asleep in [360.0, 450.0, 540.0] {
            for rhr in [48.0, 54.0, 60.0] {
                for _ in 0..<5 {
                    day += 1
                    let duration = asleep + generator.nextDouble(in: -12...12)
                    nights.append(Fixture.night(
                        daysAgo: day,
                        timeAsleepMinutes: duration,
                        timeInBedMinutes: duration / 0.9,
                        // A hair of jitter so the tercile cuts can still be
                        // made, but far too little for any cell to be
                        // genuinely better than another.
                        avgHRV: 52 + generator.nextDouble(in: -0.5...0.5),
                        restingHeartRate: rhr + generator.nextDouble(in: -2...2)
                    ))
                }
            }
        }
        let map = try XCTUnwrap(SleepMap.build(
            nights: nights.sorted { $0.date < $1.date },
            xAxis: .duration, yAxis: .restingHeartRate, outcome: .hrv
        ))

        XCTAssertFalse(map.headlineIsSupported, map.sentence)
        XCTAssertTrue(map.sentence.contains("cluster around"), map.sentence)
        XCTAssertFalse(map.sentence.contains("Your best"), map.sentence)
    }

    /// Absence of an interval is absence of evidence. The alternative lets
    /// the thinnest regions on the map produce the most confident headlines.
    func testARegionWithNoIntervalIsNeverSeparated() {
        let withInterval = SleepMap.Region(
            x: .low, y: .low, nightCount: 9, medianOutcome: 70,
            shrunkOutcome: 70, interval: SleepMap.Interval(lower: 69, upper: 71)
        )
        let without = SleepMap.Region(
            x: .high, y: .high, nightCount: 9, medianOutcome: 40, shrunkOutcome: 40
        )
        XCTAssertFalse(SleepMap.isSeparated([withInterval, without]))
        XCTAssertFalse(SleepMap.isSeparated([without, withInterval]))
    }

    /// Two regions whose intervals sit on top of each other are describing
    /// more of the same range than not.
    func testMateriallyOverlappingRegionsAreNotSeparated() {
        let a = SleepMap.Region(
            x: .low, y: .low, nightCount: 9, medianOutcome: 60,
            shrunkOutcome: 60, interval: SleepMap.Interval(lower: 55, upper: 65)
        )
        let b = SleepMap.Region(
            x: .high, y: .high, nightCount: 9, medianOutcome: 58,
            shrunkOutcome: 58, interval: SleepMap.Interval(lower: 54, upper: 64)
        )
        XCTAssertFalse(SleepMap.isSeparated([a, b]))
    }

    /// Touching at the edges is not material overlap.
    func testBarelyTouchingRegionsAreStillSeparated() {
        let a = SleepMap.Region(
            x: .low, y: .low, nightCount: 9, medianOutcome: 70,
            shrunkOutcome: 70, interval: SleepMap.Interval(lower: 65, upper: 75)
        )
        let b = SleepMap.Region(
            x: .high, y: .high, nightCount: 9, medianOutcome: 60,
            shrunkOutcome: 60, interval: SleepMap.Interval(lower: 56, upper: 66)
        )
        XCTAssertTrue(SleepMap.isSeparated([a, b]))
    }

    func testOneRegionAloneIsNeverSeparated() {
        let only = SleepMap.Region(
            x: .low, y: .low, nightCount: 9, medianOutcome: 70,
            shrunkOutcome: 70, interval: SleepMap.Interval(lower: 69, upper: 71)
        )
        XCTAssertFalse(SleepMap.isSeparated([only]))
    }
}
