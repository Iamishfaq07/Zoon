import XCTest

/// Pins the meaning of the canonical sleep-period score. Version 3 removes
/// autonomic recovery and breathing from the headline so those signals cannot
/// be counted once as sleep and again as Recovery/Vitals.
final class ScoreMeaningTests: XCTestCase {
    /// Apple Watch nights whose Deep/REM *share* varies a little from night
    /// to night. v4 compares composition, and a history where every night
    /// had exactly 18% Deep has no spread to measure against.
    private var history: [SleepNightFeatures] {
        (0..<20).map { index in
            let offset = Double(index % 5) - 2
            let asleep = 450 + 10 * offset
            return Fixture.night(
                daysAgo: index + 1, timeAsleepMinutes: asleep,
                avgHRV: 55 + 5 * offset, restingHeartRate: 54 + 2 * offset,
                avgRespiratoryRate: 14.5 + 0.5 * offset,
                deepMinutes: asleep * (0.18 + 0.01 * offset),
                remMinutes: asleep * (0.22 - 0.01 * offset),
                stageSourcePriority: .appleWatch
            )
        }
    }

    /// Tonight, staged by Apple Watch at the history's median composition
    /// unless told otherwise.
    private func watchNight(asleep: Double = 460, deepShare: Double = 0.18, remShare: Double = 0.22) -> SleepNightFeatures {
        Fixture.night(
            daysAgo: 0, timeAsleepMinutes: asleep,
            deepMinutes: asleep * deepShare, remMinutes: asleep * remShare,
            stageSourcePriority: .appleWatch
        )
    }

    private func score(_ night: SleepNightFeatures) -> SleepIntelligenceScore {
        SleepIntelligenceScore.compute(.init(
            night: night, history: history, sleepNeedMinutes: 450,
            regularityIndex: SleepIntelligenceScore.typicalRegularityIndex,
            habitualMidpointHours: nil
        ))
    }

    private func component(_ label: String, of night: SleepNightFeatures) throws -> SleepIntelligenceScore.Component {
        try XCTUnwrap(score(night).components.first { $0.label == label })
    }

    func testRecoveryAndBreathingAreNotHeadlineSleepComponents() {
        let result = score(Fixture.night(daysAgo: 0))
        XCTAssertFalse(result.components.contains { $0.label == "Recovery" })
        XCTAssertFalse(result.components.contains { $0.label == "Breathing" })
        XCTAssertEqual(
            Set(SleepIntelligenceScore.nominalWeights.map(\.component)),
            Set(["Duration", "Continuity", "Regularity", "Timing", "Stage Pattern"])
        )
    }

    func testPhysiologyChangesDoNotChangeTheSleepPeriodScore() {
        let ordinary = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 450,
            avgHRV: 55, restingHeartRate: 54, avgRespiratoryRate: 14.5,
            wristTempDeltaC: 0, breathingDisturbances: 2
        )
        let abnormal = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 450,
            avgHRV: 12, restingHeartRate: 92, avgRespiratoryRate: 26,
            wristTempDeltaC: 2.5, breathingDisturbances: 40,
            breathingDisturbancesClassification: .elevated
        )
        XCTAssertEqual(score(ordinary).percent, score(abnormal).percent)
    }

    /// Ordinary means a typical distance from the median, not zero distance:
    /// half of all nights sit further out than one MAD-scaled 0.6745. In this
    /// history (shares spread 1 point either side of 18% / 22%) that is one
    /// percentage point off the median.
    func testAnOrdinaryStagePatternNightIsTypical() throws {
        let stages = try component("Stage Pattern", of: watchNight(deepShare: 0.19, remShare: 0.21))
        XCTAssertGreaterThan(stages.normalized, 0.9)
        XCTAssertEqual(stages.role, .typical)
        XCTAssertEqual(stages.pointContribution, 0, accuracy: 0.3)
    }

    /// Exactly on the median is the best case the curve allows. It may read
    /// as helping, but at a 5% weight it is worth well under a point.
    func testAMedianStagePatternNightHelpsByUnderHalfAPoint() throws {
        let stages = try component("Stage Pattern", of: watchNight())
        XCTAssertEqual(stages.normalized, 1, accuracy: 0.0001)
        XCTAssertLessThan(stages.pointContribution, 0.5)
        XCTAssertGreaterThanOrEqual(stages.pointContribution, 0)
    }

    func testContributorListsPartitionComponents() {
        let result = score(Fixture.night(daysAgo: 0, timeAsleepMinutes: 460))
        XCTAssertEqual(
            result.positiveContributors.count + result.negativeContributors.count + result.typicalContributors.count,
            result.components.count
        )
    }

    func testStagePatternNameAndDetailMatchMeaning() throws {
        let stages = try component("Stage Pattern", of: watchNight())
        XCTAssertTrue(stages.detail.hasPrefix("Deep "), stages.detail)
        XCTAssertTrue(stages.detail.contains("%"), "v4 states composition: \(stages.detail)")
        XCTAssertTrue(stages.detail.contains("usually"), stages.detail)
        XCTAssertFalse(score(Fixture.night(daysAgo: 0)).components.contains { $0.label == "Architecture" })
    }

    /// Distance from the person's own mix, in either direction. This used to
    /// vary the night's *duration* (480 vs 420 minutes) and expect a stage
    /// penalty -- which was the v3 double count itself. It now varies the
    /// Deep share at a fixed duration.
    func testUnusuallyHighAndLowDeepSleepScoreSymmetrically() throws {
        let more = try component("Stage Pattern", of: watchNight(deepShare: 0.24, remShare: 0.16))
        let less = try component("Stage Pattern", of: watchNight(deepShare: 0.12, remShare: 0.28))
        XCTAssertEqual(more.normalized, less.normalized, accuracy: 0.02)
        XCTAssertLessThan(more.normalized, 0.85)
    }

    func testScoringVersionMovedWithMeaning() {
        XCTAssertEqual(SleepIntelligenceScore.currentVersion, 4)
        XCTAssertEqual(score(Fixture.night(daysAgo: 0)).scoringVersion, 4)
    }
}
