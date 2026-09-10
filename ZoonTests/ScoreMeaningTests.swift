import XCTest

/// Pins the meaning of the canonical sleep-period score. Version 3 removes
/// autonomic recovery and breathing from the headline so those signals cannot
/// be counted once as sleep and again as Recovery/Vitals.
final class ScoreMeaningTests: XCTestCase {
    private var history: [SleepNightFeatures] {
        (0..<20).map { index in
            let offset = Double(index % 5) - 2
            return Fixture.night(
                daysAgo: index + 1, timeAsleepMinutes: 450 + 10 * offset,
                avgHRV: 55 + 5 * offset, restingHeartRate: 54 + 2 * offset,
                avgRespiratoryRate: 14.5 + 0.5 * offset
            )
        }
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

    func testAnOrdinaryStagePatternNightIsTypical() throws {
        let stages = try component("Stage Pattern", of: Fixture.night(daysAgo: 0, timeAsleepMinutes: 460))
        XCTAssertGreaterThan(stages.normalized, 0.9)
        XCTAssertEqual(stages.role, .typical)
        XCTAssertEqual(stages.pointContribution, 0, accuracy: 0.3)
    }

    func testContributorListsPartitionComponents() {
        let result = score(Fixture.night(daysAgo: 0, timeAsleepMinutes: 460))
        XCTAssertEqual(
            result.positiveContributors.count + result.negativeContributors.count + result.typicalContributors.count,
            result.components.count
        )
    }

    func testStagePatternNameAndDetailMatchMeaning() throws {
        let stages = try component("Stage Pattern", of: Fixture.night(daysAgo: 0, timeAsleepMinutes: 460))
        XCTAssertTrue(stages.detail.hasPrefix("Deep "), stages.detail)
        XCTAssertTrue(stages.detail.contains("usually"), stages.detail)
        XCTAssertFalse(score(Fixture.night(daysAgo: 0)).components.contains { $0.label == "Architecture" })
    }

    func testUnusuallyHighAndLowDeepSleepScoreSymmetrically() throws {
        let more = try component("Stage Pattern", of: Fixture.night(daysAgo: 0, timeAsleepMinutes: 480))
        let less = try component("Stage Pattern", of: Fixture.night(daysAgo: 0, timeAsleepMinutes: 420))
        XCTAssertEqual(more.normalized, less.normalized, accuracy: 0.02)
        XCTAssertLessThan(more.normalized, 0.85)
    }

    func testScoringVersionMovedWithMeaning() {
        XCTAssertEqual(SleepIntelligenceScore.currentVersion, 3)
        XCTAssertEqual(score(Fixture.night(daysAgo: 0)).scoringVersion, 3)
    }
}
