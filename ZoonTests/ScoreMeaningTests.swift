import XCTest

/// What a Sleep Intelligence component's number means.
///
/// Three V9 items, all inside this one type, all changing what the score says
/// rather than how it is plumbed -- hence one `currentVersion` bump covering
/// the three of them.
///
/// ## Why the fixtures look the way they do
///
/// `Statistics.robustZ` returns nil when a metric has no spread, so a history
/// of twenty identical nights produces no Recovery, Breathing or Stage
/// Pattern component at all and every assertion below would pass vacuously.
/// The history therefore cycles a five-value pattern, which makes each
/// metric's median and MAD exact and lets a fixture sit at a chosen z by
/// construction.
///
/// The second thing the fixtures encode is subtler and is the reason an
/// earlier draft of this file was wrong. For a component scored on `abs(z)`,
/// a night sitting *exactly* on the median is not typical -- it is unusually
/// close to centre, and reporting it as helpful is correct. The typical night
/// is one MAD out. So "an ordinary night" means z = 0 on the signed curves
/// and |z| = 0.6745 on the distance ones, and the fixtures below place each
/// metric accordingly.
final class ScoreMeaningTests: XCTestCase {

    /// Twenty nights whose medians are exactly the base values below, with
    /// enough spread for `robustZ` to work.
    private var history: [SleepNightFeatures] {
        (0..<20).map { index in
            let offset = Double(index % 5) - 2   // -2, -1, 0, 1, 2
            return Fixture.night(
                daysAgo: index + 1,
                timeAsleepMinutes: 450 + 10 * offset,
                avgHRV: 55 + 5 * offset,
                restingHeartRate: 54 + 2 * offset,
                avgRespiratoryRate: 14.5 + 0.5 * offset,
                wristTempDeltaC: 0.1 * offset,
                breathingDisturbances: nil
            )
        }
    }

    /// A night that is ordinary for this person on every axis: on the median
    /// where the curve is signed, one MAD out where it measures distance.
    private func ordinaryNight(
        breathingDisturbances: Double? = nil,
        classification: BreathingDisturbanceClassification? = nil
    ) -> SleepNightFeatures {
        Fixture.night(
            daysAgo: 0,
            timeAsleepMinutes: 460,        // deep and REM one MAD from median
            avgHRV: 55,                    // z = 0
            restingHeartRate: 54,          // z = 0
            avgRespiratoryRate: 15.0,      // |z| = 0.6745
            wristTempDeltaC: 0.1,          // |z| = 0.6745
            breathingDisturbances: breathingDisturbances,
            breathingDisturbancesClassification: classification
        )
    }

    private func score(_ night: SleepNightFeatures) -> SleepIntelligenceScore {
        SleepIntelligenceScore.compute(.init(
            night: night,
            history: history,
            sleepNeedMinutes: 450,
            regularityIndex: SleepIntelligenceScore.typicalRegularityIndex,
            habitualMidpointHours: nil
        ))
    }

    private func component(
        _ label: String,
        of night: SleepNightFeatures,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SleepIntelligenceScore.Component {
        try XCTUnwrap(
            score(night).components.first { $0.label == label },
            "no \(label) component", file: file, line: line
        )
    }

    // MARK: - Item 15: 0.5 was not the middle of anything

    /// The headline of the whole change.
    ///
    /// An HRV sitting exactly on this person's own median normalizes to 0.65,
    /// because the curve is asymmetric -- HRV has further to fall than to
    /// rise. Measured against a neutral of 0.5, an utterly ordinary night was
    /// reported as one where the user's recovery was *helping* the score.
    func testAnOrdinaryRecoveryNightIsTypicalNotHelpful() throws {
        let recovery = try component("Recovery", of: ordinaryNight())

        XCTAssertGreaterThan(
            recovery.normalized, 0.5,
            "below 0.5 the fixture has stopped exercising the bug"
        )
        // What the old formula would have reported, for the record.
        XCTAssertGreaterThan((recovery.normalized - 0.5) * recovery.weightUsed * 100, 1.0)

        XCTAssertEqual(recovery.role, .typical)
        XCTAssertEqual(recovery.pointContribution, 0, accuracy: 0.5)
    }

    /// Same statement for the component whose curve sits furthest from 0.5:
    /// a night at a typical distance from your own stage split scores ~0.93.
    func testAnOrdinaryStagePatternNightIsTypicalNotHelpful() throws {
        let stages = try component("Stage Pattern", of: ordinaryNight())

        XCTAssertGreaterThan(stages.normalized, 0.9)
        XCTAssertEqual(stages.role, .typical)
        XCTAssertEqual(stages.pointContribution, 0, accuracy: 0.3)
    }

    func testAnOrdinaryBreathingNightIsTypical() throws {
        let breathing = try component("Breathing", of: ordinaryNight())
        XCTAssertGreaterThan(breathing.normalized, 0.5)
        XCTAssertEqual(breathing.role, .typical)
    }

    /// A night sitting *exactly* on the median of a distance-based component
    /// is unusually close to centre, and saying so is correct. Pinned so the
    /// asymmetry with the test above reads as deliberate.
    func testBeingExactlyOnYourOwnMedianIsBetterThanTypical() throws {
        let deadOn = Fixture.night(
            daysAgo: 0,
            timeAsleepMinutes: 450,
            avgHRV: 55,
            restingHeartRate: 54,
            avgRespiratoryRate: 14.5,
            wristTempDeltaC: 0.0,
            breathingDisturbances: nil
        )
        let stages = try component("Stage Pattern", of: deadOn)
        XCTAssertEqual(stages.role, .helpful)
    }

    /// The three lists must partition `components`. They used to filter on a
    /// +/-0.5 point threshold of their own, unrelated to what counts as an
    /// ordinary night, so a component could be in neither list and also not
    /// be graded typical.
    func testTheThreeContributorListsPartitionTheComponents() {
        let result = score(ordinaryNight())
        XCTAssertFalse(result.components.isEmpty)
        XCTAssertEqual(
            result.positiveContributors.count
                + result.negativeContributors.count
                + result.typicalContributors.count,
            result.components.count
        )
    }

    /// The fix must not flatten everything into "typical".
    func testAnUnusuallyGoodNightStillRegistersAsHelpful() throws {
        let good = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 460,
            avgHRV: 85, restingHeartRate: 46,
            avgRespiratoryRate: 15.0, wristTempDeltaC: 0.1,
            breathingDisturbances: nil
        )
        let recovery = try component("Recovery", of: good)
        XCTAssertEqual(recovery.role, .helpful)
        XCTAssertGreaterThan(recovery.pointContribution, 0)
    }

    func testAPoorNightRegistersAsLimiting() throws {
        let poor = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 460,
            avgHRV: 25, restingHeartRate: 68,
            avgRespiratoryRate: 15.0, wristTempDeltaC: 0.1,
            breathingDisturbances: nil
        )
        let recovery = try component("Recovery", of: poor)
        XCTAssertEqual(recovery.role, .limiting)
        XCTAssertLessThan(recovery.pointContribution, 0)
    }

    // MARK: - Item 13: no invented clinical severity scale

    /// The removed table scored a 15% disturbance rate at 55/100 on nothing
    /// but its own authority. Apple says this night was not elevated, nothing
    /// in Zoon knows better, so the night is not marked down for it.
    func testAppleSayingNotElevatedMeansTheNumberIsNotGradedAgain() throws {
        let breathing = try component(
            "Breathing",
            of: ordinaryNight(breathingDisturbances: 15, classification: .notElevated)
        )
        XCTAssertEqual(breathing.role, .typical)
    }

    func testAppleSayingElevatedCostsTheNightGround() throws {
        let breathing = try component(
            "Breathing",
            of: ordinaryNight(breathingDisturbances: 15, classification: .elevated)
        )
        XCTAssertEqual(breathing.role, .limiting)
        XCTAssertLessThan(breathing.pointContribution, 0)
    }

    /// Same measured percentage, opposite classifications, different scores --
    /// otherwise the classification is not actually being used.
    func testTheClassificationAndNotThePercentageDecides() throws {
        let notElevated = try component(
            "Breathing", of: ordinaryNight(breathingDisturbances: 15, classification: .notElevated)
        )
        let elevated = try component(
            "Breathing", of: ordinaryNight(breathingDisturbances: 15, classification: .elevated)
        )
        XCTAssertGreaterThan(notElevated.normalized, elevated.normalized)
    }

    // MARK: - Item 14: the concept is named what it measures

    func testTheComponentIsCalledStagePattern() {
        let result = score(ordinaryNight())
        XCTAssertTrue(result.components.contains { $0.label == "Stage Pattern" })
        XCTAssertFalse(result.components.contains { $0.label == "Architecture" })
        XCTAssertTrue(
            SleepIntelligenceScore.nominalWeights.contains { $0.component == "Stage Pattern" }
        )
    }

    /// The behaviour the rename exists for. `abs(z)` marks an unusually high
    /// deep-sleep night down exactly as far as an unusually low one -- which
    /// is defensible for "how close is this to your pattern" and indefensible
    /// for anything called "Architecture Quality".
    func testUnusuallyHighAndUnusuallyLowDeepSleepScoreTheSame() throws {
        // Fixture stages scale with duration, so these sit symmetrically
        // either side of the median stage split.
        // 480 and 420 put both nights at |z| ~ 2.0, inside the curve rather
        // than clamped at its far anchor -- two values that are equal only
        // because both saturated would prove nothing.
        let more = try component("Stage Pattern", of: Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 480, breathingDisturbances: nil
        ))
        let less = try component("Stage Pattern", of: Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 420, breathingDisturbances: nil
        ))
        XCTAssertEqual(more.normalized, less.normalized, accuracy: 0.02)
        XCTAssertLessThan(more.normalized, 0.85, "both nights clamped; the test proves nothing")
    }

    func testTheDetailShowsThePersonalRange() throws {
        let stages = try component("Stage Pattern", of: ordinaryNight())
        XCTAssertTrue(stages.detail.hasPrefix("Deep "), stages.detail)
        XCTAssertTrue(stages.detail.contains("usually"), stages.detail)
    }

    // MARK: - Versioning

    /// All three items change what the number means, so history scored under
    /// the old model has to stay identifiable as such.
    func testTheScoringVersionMovedWithTheMeaning() {
        XCTAssertEqual(SleepIntelligenceScore.currentVersion, 2)
        XCTAssertEqual(score(ordinaryNight()).scoringVersion, 2)
    }
}
