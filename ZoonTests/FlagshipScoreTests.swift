import XCTest

/// One score, on every piece of glass.
///
/// The phone's hero, its Last Night card and the watch's Sleep page lead with
/// Sleep Intelligence. The watch's Last Night page, both home screen widgets,
/// the complication gauge and the Siri response led with `score` -- the older
/// `SleepScore`. Same night, two numbers, and nothing to tell the reader they
/// were answering different questions.
final class FlagshipScoreTests: XCTestCase {

    private func snapshot(
        score: Int,
        intelligence: Int? = nil
    ) -> SleepSnapshot {
        SleepSnapshot(
            features: Fixture.night(daysAgo: 1),
            score: SleepScore(value: score, components: []),
            insight: SleepInsight(
                summary: "summary",
                likelyCause: "cause",
                actionableTip: "tip",
                confidence: .medium
            ),
            goalMinutes: 480,
            sleepIntelligencePercent: intelligence ?? 0,
            sleepIntelligenceBand: intelligence.map {
                SleepIntelligenceScore.Band.forPercent($0).label
            } ?? "",
            sleepIntelligenceVersion: intelligence == nil
                ? 0 : SleepIntelligenceScore.currentVersion
        )
    }

    func testTheFlagshipIsSleepIntelligenceWhenItIsThere() {
        let payload = snapshot(score: 81, intelligence: 64)
        XCTAssertTrue(payload.hasSleepIntelligence)
        XCTAssertEqual(payload.flagshipScore, 64)
        XCTAssertEqual(payload.flagshipBand, "Fair")
        // The older score is still carried -- it is the fallback, not a
        // second opinion -- but nothing displays it.
        XCTAssertEqual(payload.score, 81)
    }

    /// A watch or a widget can hold a payload written before the phone was
    /// updated. Showing the older number beats showing nothing; showing zero
    /// would be a lie.
    func testAPayloadWithoutSleepIntelligenceFallsBackRatherThanShowingZero() {
        let payload = snapshot(score: 81)
        XCTAssertFalse(payload.hasSleepIntelligence)
        XCTAssertEqual(payload.flagshipScore, 81)
        XCTAssertEqual(payload.flagshipBand, payload.scoreBand)
        XCTAssertNotEqual(payload.flagshipScore, 0)
    }

    /// Both halves have to be present. A version with no band, or a band with
    /// no version, is a partial payload rather than a score.
    func testHalfAPayloadIsNotASleepIntelligenceScore() {
        var partial = snapshot(score: 81, intelligence: 64)
        partial.sleepIntelligenceBand = ""
        XCTAssertFalse(partial.hasSleepIntelligence)
        XCTAssertEqual(partial.flagshipScore, 81)

        var unversioned = snapshot(score: 81, intelligence: 64)
        unversioned.sleepIntelligenceVersion = 0
        XCTAssertFalse(unversioned.hasSleepIntelligence)
        XCTAssertEqual(unversioned.flagshipScore, 81)
    }

    func testTheVersionSurvivesTheWireLikeEveryOtherField() throws {
        let payload = snapshot(score: 81, intelligence: 64)
        let decoded = try JSONDecoder().decode(
            SleepSnapshot.self, from: JSONEncoder().encode(payload)
        )
        XCTAssertEqual(decoded.sleepIntelligenceVersion, SleepIntelligenceScore.currentVersion)
        XCTAssertEqual(decoded.flagshipScore, 64)
        XCTAssertEqual(decoded.flagshipBand, "Fair")
    }

    /// The two band tables are independent definitions that happen to agree.
    /// `SleepScoreWidget` colours the number from the Sleep Intelligence
    /// table and labels it from whichever score the payload carried, so if
    /// either table moves the colour and the word stop matching -- silently,
    /// and only on the fallback path, which is the hardest place to notice.
    func testTheTwoBandTablesAgreeAtEveryValue() {
        for percent in 0...100 {
            XCTAssertEqual(
                SleepIntelligenceScore.Band.forPercent(percent).label,
                SleepScore.Band.forValue(percent).label,
                "band tables disagree at \(percent)"
            )
        }
    }

    func testBandBoundaries() {
        XCTAssertEqual(SleepIntelligenceScore.Band.forPercent(49), .poor)
        XCTAssertEqual(SleepIntelligenceScore.Band.forPercent(50), .fair)
        XCTAssertEqual(SleepIntelligenceScore.Band.forPercent(69), .fair)
        XCTAssertEqual(SleepIntelligenceScore.Band.forPercent(70), .good)
        XCTAssertEqual(SleepIntelligenceScore.Band.forPercent(84), .good)
        XCTAssertEqual(SleepIntelligenceScore.Band.forPercent(85), .excellent)
    }

    // MARK: - Declining to state a number

    /// The watch shows a recovery number only when the phone says it can
    /// stand behind one. `RecoveryScore` already separates the score from
    /// the confidence in it (V9 item 4); before this, the watch took the
    /// number and dropped the caveat on the way.
    func testARecoveryScoreWithEnoughBehindItIsStated() {
        for confidence in [MetricConfidence.low, .moderate, .high] {
            var payload = snapshot(score: 70, intelligence: 70)
            payload.recoveryConfidence = confidence.rawValue
            XCTAssertTrue(payload.canStateRecovery, "\(confidence.rawValue) should still be shown")
        }
    }

    /// `.insufficient` is the one band `RecoveryScore` itself says is not
    /// enough to state. Below it the score is arithmetic over gaps.
    func testAnInsufficientRecoveryScoreIsNotStated() {
        var payload = snapshot(score: 70, intelligence: 70)
        payload.recoveryConfidence = MetricConfidence.insufficient.rawValue
        XCTAssertFalse(payload.canStateRecovery)
    }

    /// A snapshot written before the field existed came from a build that
    /// showed the number unconditionally. Hiding it retroactively would read
    /// on the wrist as lost data rather than as new honesty.
    func testASnapshotFromBeforeTheFieldExistedStillShowsItsNumber() {
        var payload = snapshot(score: 70, intelligence: 70)
        payload.recoveryConfidence = ""
        XCTAssertTrue(payload.canStateRecovery)
    }

    /// Anything the enum does not recognise is treated the same way as an
    /// absent value: shown. A future writer sending a band this build has
    /// never heard of is not evidence that the number is bad.
    func testAnUnrecognisedConfidenceIsTreatedAsAbsentRatherThanAsInsufficient() {
        var payload = snapshot(score: 70, intelligence: 70)
        payload.recoveryConfidence = "provisional"
        XCTAssertTrue(payload.canStateRecovery)
    }
}
