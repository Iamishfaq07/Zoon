import XCTest

/// The phone's hero has printed "Low confidence · 40% data coverage" beside
/// the Sleep Intelligence score for a while. The widgets, the watch and the
/// complications printed the same number bare -- and the score can genuinely
/// be `.insufficient`, for a night that produced nothing but a sleep-minutes
/// figure. These pin the gate that closes that gap.
final class SleepIntelligenceStatabilityTests: XCTestCase {

    private func payload(
        confidence: MetricConfidence?,
        percent: Int? = 74,
        fallbackScore: Int = 62
    ) -> SleepSnapshot {
        var snapshot = SleepSnapshot(
            features: Fixture.night(daysAgo: 1),
            score: SleepScore(value: fallbackScore, components: []),
            insight: SleepInsight(
                summary: "summary",
                likelyCause: "cause",
                actionableTip: "tip",
                confidence: .medium
            ),
            goalMinutes: 480,
            sleepIntelligencePercent: percent ?? 0,
            sleepIntelligenceBand: percent.map {
                SleepIntelligenceScore.Band.forPercent($0).label
            } ?? "",
            sleepIntelligenceVersion: percent == nil ? 0 : SleepIntelligenceScore.currentVersion
        )
        snapshot.sleepIntelligenceConfidence = confidence?.rawValue ?? ""
        return snapshot
    }

    func testAStatableScoreIsPrinted() {
        for confidence: MetricConfidence in [.low, .moderate, .high] {
            let snapshot = payload(confidence: confidence)
            XCTAssertTrue(snapshot.canStateSleepIntelligence, "\(confidence) is weak, not absent")
            XCTAssertEqual(snapshot.flagshipScoreText, "74")
        }
    }

    func testInsufficientConfidenceWithholdsTheNumber() {
        let snapshot = payload(confidence: .insufficient)
        XCTAssertFalse(snapshot.canStateSleepIntelligence)
        XCTAssertFalse(snapshot.canStateFlagshipScore)
        XCTAssertEqual(snapshot.flagshipScoreText, "—", "a glance surface shows a dash, not a number")
        XCTAssertEqual(snapshot.flagshipScore, 74, "the value is still there for the ring to draw")
    }

    /// Same rule `canStateRecovery` already applies. Those payloads came from
    /// a build that showed the number unconditionally, and hiding it
    /// retroactively reads on the wrist as lost data rather than as honesty.
    func testLegacyPayloadWithNoConfidenceStillStatesTheScore() {
        let snapshot = payload(confidence: nil)
        XCTAssertTrue(snapshot.canStateSleepIntelligence)
        XCTAssertEqual(snapshot.flagshipScoreText, "74")
    }

    func testUnrecognisedConfidenceIsTreatedAsLegacy() {
        var snapshot = payload(confidence: nil)
        snapshot.sleepIntelligenceConfidence = "provisional"
        XCTAssertTrue(snapshot.canStateSleepIntelligence, "an unknown label is not a refusal")
    }


    /// With no Sleep Intelligence in the payload the flagship falls back to
    /// the older `score`, which records no confidence -- so there is nothing
    /// to withhold and the behaviour is unchanged.
    func testFallbackScoreIsUnaffected() {
        let snapshot = payload(confidence: .insufficient, percent: nil, fallbackScore: 62)

        XCTAssertFalse(snapshot.hasSleepIntelligence)
        XCTAssertFalse(snapshot.canStateSleepIntelligence)
        XCTAssertTrue(snapshot.canStateFlagshipScore, "the older score is what is being shown here")
        XCTAssertEqual(snapshot.flagshipScoreText, "62")
    }

    func testConfidenceSurvivesTheWire() throws {
        let original = payload(confidence: .insufficient)
        let decoded = try JSONDecoder().decode(
            SleepSnapshot.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded.sleepIntelligenceConfidence, MetricConfidence.insufficient.rawValue)
        XCTAssertFalse(decoded.canStateFlagshipScore)
    }

    /// Built by stripping the key from a real payload rather than by hand, so
    /// the fixture cannot drift from the shape the encoder actually writes.
    func testFieldAbsentFromAnOlderPayloadDecodesAsUnknown() throws {
        let encoded = try JSONEncoder().encode(payload(confidence: .insufficient))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNotNil(object.removeValue(forKey: "sleepIntelligenceConfidence"))

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SleepSnapshot.self, from: legacy)

        XCTAssertEqual(decoded.sleepIntelligenceConfidence, "")
        XCTAssertTrue(decoded.canStateFlagshipScore, "an older payload keeps showing its number")
    }
}
