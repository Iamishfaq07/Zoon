import XCTest

/// A withheld score must not be drawn as a ring.
///
/// `flagshipScoreText` already gated the *number* on every glance surface, and
/// they all used it. Nothing gated the *shape*, so the watch dial, both
/// circular widget gauges and the circular complication printed "—" in the
/// middle of a ring filled to the real score — withholding the precision
/// while keeping the claim. A ring two thirds of the way round says "about
/// two thirds" whether or not the digits are there.
///
/// The phone already applied the stricter rule (`HealthPulseStrip` draws no
/// arc when the score is withheld). `flagshipGaugeValue` is that rule, in one
/// place, for the surfaces that were arguing the opposite.
final class FlagshipGaugeTests: XCTestCase {

    func testAStatableScoreDrawsToItsValue() {
        for confidence: MetricConfidence in [.low, .moderate, .high] {
            let snapshot = payload(percent: 74, confidence: confidence)
            XCTAssertEqual(
                snapshot.flagshipGaugeValue, 74, accuracy: 0.001,
                "\(confidence) is weak, not absent — the ring should still draw"
            )
        }
    }

    func testAWithheldScoreDrawsNothing() {
        let snapshot = payload(percent: 74, confidence: .insufficient)

        XCTAssertEqual(snapshot.flagshipScoreText, "—", "precondition: the number is withheld")
        XCTAssertEqual(
            snapshot.flagshipGaugeValue, 0, accuracy: 0.001,
            "an empty track is the only honest ring for a number we won't state"
        )
    }

    /// The text gate and the shape gate must never disagree: a dash beside a
    /// filled ring is the exact combination this type exists to prevent.
    func testTextAndShapeAgreeAcrossEveryConfidence() {
        let confidences: [MetricConfidence?] = [nil, .insufficient, .low, .moderate, .high]
        for confidence in confidences {
            let snapshot = payload(percent: 74, confidence: confidence)
            let withheldText = snapshot.flagshipScoreText == "—"
            let emptyRing = snapshot.flagshipGaugeValue == 0

            XCTAssertEqual(
                withheldText, emptyRing,
                "confidence \(String(describing: confidence)): text says "
                    + (withheldText ? "withheld" : "stated")
                    + " but the ring is " + (emptyRing ? "empty" : "filled")
            )
        }
    }

    /// A payload with no Sleep Intelligence at all falls back to the older
    /// `score`, which carries no confidence to withhold on. Behaviour there is
    /// unchanged, and the ring draws — this pass must not have made older
    /// payloads render as blank rings.
    func testLegacyPayloadWithoutIntelligenceStillDraws() {
        let snapshot = payload(percent: nil, confidence: nil, fallbackScore: 81)

        XCTAssertFalse(snapshot.hasSleepIntelligence)
        XCTAssertEqual(snapshot.flagshipScoreText, "81")
        XCTAssertEqual(snapshot.flagshipGaugeValue, 81, accuracy: 0.001)
    }

    /// `Gauge(value:in: 0...100)` clamps nothing itself, so a payload carrying
    /// a score above 100 must not push the needle past the track.
    func testValueIsClampedToTheTrack() {
        let snapshot = payload(percent: 140, confidence: .high)
        XCTAssertEqual(snapshot.flagshipGaugeValue, 100, accuracy: 0.001)
    }

    private func payload(
        percent: Int?,
        confidence: MetricConfidence?,
        fallbackScore: Int = 70
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
}
