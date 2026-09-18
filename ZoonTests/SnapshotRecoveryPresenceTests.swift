import XCTest

/// "Missing is not zero", at the one place a default quietly said otherwise.
final class SnapshotRecoveryPresenceTests: XCTestCase {

    private var base: SleepSnapshot {
        SleepSnapshot(
            features: Fixture.night(daysAgo: 1),
            score: SleepScore.compute(for: Fixture.night(daysAgo: 1), goalMinutes: 480),
            insight: SleepInsight(
                summary: "s", likelyCause: "c", actionableTip: "t", confidence: .medium
            ),
            goalMinutes: 480
        )
    }

    /// The defect the watch render exposed.
    ///
    /// `hasRecovery` defaulted to `true` beside a percent defaulting to 0, so
    /// a caller naming neither produced a snapshot asserting a recovery
    /// reading of zero -- and the watch drew it as a dial reading "0
    /// RECOVERY". The default that means "I was not told" has to be the one
    /// claiming least.
    func testASnapshotToldNothingDoesNotClaimARecoveryOfZero() {
        let snapshot = base
        XCTAssertEqual(snapshot.recoveryPercent, 0, "the premise: no percent was given")
        XCTAssertFalse(snapshot.hasRecovery, "absence was reported as a reading of zero")
        XCTAssertFalse(snapshot.canStateRecovery, "a zero would have been drawn on the watch")
    }

    /// Saying so explicitly still works, in both directions -- the fix must
    /// not have turned the flag into a constant.
    func testAStatedRecoveryIsStillStated() {
        var stated = base
        stated.recoveryPercent = 72
        stated.hasRecovery = true
        stated.recoveryConfidence = MetricConfidence.moderate.rawValue
        XCTAssertTrue(stated.canStateRecovery)

        var withheld = stated
        withheld.hasRecovery = false
        XCTAssertFalse(withheld.canStateRecovery)
    }

    /// Insufficient confidence still withholds, which is the gate the live
    /// path was relying on. Asserted so the fix above is understood as a
    /// second lock rather than a replacement for this one.
    func testInsufficientConfidenceStillWithholds() {
        var snapshot = base
        snapshot.recoveryPercent = 72
        snapshot.hasRecovery = true
        snapshot.recoveryConfidence = MetricConfidence.insufficient.rawValue
        XCTAssertFalse(snapshot.canStateRecovery)
    }

    /// The demo snapshot has a reading to show, or the watch's TODAY page
    /// photographs an empty state in every screenshot.
    func testTheDemoSnapshotCanStateRecovery() {
        XCTAssertTrue(MockData.snapshot.canStateRecovery)
        XCTAssertGreaterThan(MockData.snapshot.recoveryPercent, 0)
        XCTAssertTrue(MockData.snapshotWithBadges.canStateRecovery)
    }
}
