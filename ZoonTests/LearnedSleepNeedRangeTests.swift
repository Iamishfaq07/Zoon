import XCTest

/// §9. The learned baseline is a 60th percentile printed to the minute, from
/// a distribution that is nothing like a single number. On its own it reads as
/// a measurement of how much sleep a body requires; it is where the middle of
/// somebody's unconstrained nights landed.
final class LearnedSleepNeedRangeTests: XCTestCase {

    /// Nights that clear the quality filter: efficient, unfragmented, not
    /// restriction-shaped, not repaying debt.
    private func qualifyingNights(
        _ durations: [Double],
        goalMinutes: Double = 480
    ) -> [SleepNightFeatures] {
        durations.enumerated().map { index, asleep in
            Fixture.night(
                daysAgo: index + 1,
                timeAsleepMinutes: asleep,
                // Efficiency about 90%: clears the 85% floor without tripping
                // the 95% restriction ceiling.
                timeInBedMinutes: asleep / 0.90,
                sleepDebtMinutes: 0,
                wakeCount: 1
            )
        }
    }

    private func compute(_ durations: [Double], goal: Double = 480) -> LearnedSleepNeed {
        LearnedSleepNeed.compute(
            goalMinutes: goal, history: qualifyingNights(durations, goalMinutes: goal)
        )
    }

    /// Enough nights to clear `fullConfidenceNights`, centred on `centre`
    /// with a spread of `spread` minutes either way.
    private func spreadDurations(centre: Double, spread: Double, count: Int = 70) -> [Double] {
        (0..<count).map { index in
            let position = Double(index) / Double(max(count - 1, 1)) - 0.5
            return centre + position * 2 * spread
        }
    }

    // MARK: - The band exists where it is earned

    func testAThinHistoryCarriesNoRange() {
        let thin = compute(Array(repeating: 460, count: 5))
        XCTAssertNil(thin.learnedMinutes)
        XCTAssertNil(thin.typicalLowMinutes)
        XCTAssertNil(thin.typicalHighMinutes)
        XCTAssertFalse(thin.showsRange)
    }

    /// A band implies the distribution behind it is real. Below moderate
    /// confidence the figure is mostly still the person's stated goal, and
    /// drawing a band around a goal dresses a preference up as an observation.
    func testARangeIsOnlyShownOnceConfidenceIsAtLeastModerate() {
        let learned = compute(spreadDurations(centre: 470, spread: 40))
        XCTAssertGreaterThanOrEqual(learned.confidence, .moderate)
        XCTAssertTrue(learned.showsRange)
    }

    func testTheBandBracketsTheEstimate() throws {
        let learned = compute(spreadDurations(centre: 470, spread: 40))
        let low = try XCTUnwrap(learned.typicalLowMinutes)
        let high = try XCTUnwrap(learned.typicalHighMinutes)
        let estimate = try XCTUnwrap(learned.learnedMinutes)

        XCTAssertLessThanOrEqual(low, estimate)
        XCTAssertLessThanOrEqual(estimate, high)
    }

    // MARK: - The width is observed, not fabricated

    /// The point of deriving the band from the nights: a metronomic sleeper
    /// and an erratic one must not be told the same thing. A fixed ±20 would
    /// have told them exactly the same thing.
    func testAnErraticSleeperGetsAWiderBandThanASteadyOne() throws {
        let steady = compute(spreadDurations(centre: 470, spread: 8))
        let erratic = compute(spreadDurations(centre: 470, spread: 70))

        let steadyWidth = try XCTUnwrap(steady.typicalHighMinutes) - try XCTUnwrap(steady.typicalLowMinutes)
        let erraticWidth = try XCTUnwrap(erratic.typicalHighMinutes) - try XCTUnwrap(erratic.typicalLowMinutes)

        XCTAssertGreaterThan(erraticWidth, steadyWidth)
    }

    /// And the dispersion figure moves with them, for callers that want the
    /// width rather than the band.
    func testTheSpreadFigureTracksTheActualVariability() throws {
        let steady = try XCTUnwrap(compute(spreadDurations(centre: 470, spread: 8)).spreadMinutes)
        let erratic = try XCTUnwrap(compute(spreadDurations(centre: 470, spread: 70)).spreadMinutes)
        XCTAssertGreaterThan(erratic, steady)
    }

    /// A person who sleeps the same length every night has no meaningful
    /// spread, and the band must collapse rather than inventing one.
    func testAPerfectlyRegularSleeperGetsNoWidth() throws {
        let identical = compute(Array(repeating: 470.0, count: 70))
        let low = try XCTUnwrap(identical.typicalLowMinutes)
        let high = try XCTUnwrap(identical.typicalHighMinutes)
        XCTAssertEqual(high - low, 0, accuracy: 0.001)
    }

    // MARK: - The failure the brief names

    /// "A user repeatedly getting 6h15 with high efficiency must not teach
    /// the system that 6h15 is necessarily sufficient."
    ///
    /// Already handled by `isRestrictionShaped`, and asserted here because it
    /// is the specific failure the audit calls out — a chronic short sleeper
    /// with measured time in bed and very high efficiency contributes no
    /// qualifying nights at all.
    func testAChronicShortSleeperTeachesTheModelNothing() {
        let restricted = (1...60).map { index in
            Fixture.night(
                daysAgo: index,
                timeAsleepMinutes: 375,          // 6h15
                timeInBedMinutes: 385,           // ~97% efficiency, measured
                sleepDebtMinutes: 0,
                wakeCount: 0
            )
        }
        let learned = LearnedSleepNeed.compute(goalMinutes: 480, history: restricted)
        XCTAssertEqual(learned.qualifyingNightCount, 0)
        XCTAssertNil(learned.learnedMinutes)
        XCTAssertEqual(learned.minutes, 480, accuracy: 0.001, "the stated goal should survive untouched")
    }

    // MARK: - Round trip

    /// The new fields are optional so a record written before they existed
    /// still decodes — as absent, which is the truth about those records.
    func testARecordWithoutTheNewFieldsStillDecodes() throws {
        let json = """
        {"minutes":470,"qualifyingNightCount":40,"confidence":"moderate"}
        """
        let decoded = try JSONDecoder().decode(LearnedSleepNeed.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.minutes, 470)
        XCTAssertNil(decoded.typicalLowMinutes)
        XCTAssertFalse(decoded.showsRange, "an old record must not claim a range it never had")
    }

    func testAFullRecordSurvivesARoundTrip() throws {
        let learned = compute(spreadDurations(centre: 470, spread: 40))
        let data = try JSONEncoder().encode(learned)
        XCTAssertEqual(try JSONDecoder().decode(LearnedSleepNeed.self, from: data), learned)
    }
}
