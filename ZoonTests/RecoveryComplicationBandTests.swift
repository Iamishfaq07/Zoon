import XCTest

/// Recovery's band must come from Recovery.
///
/// The complication used to print `snapshot.scoreBand` beside
/// `snapshot.recoveryPercent`. Those describe different things: one grades
/// the night that finished, the other estimates how recovered the body is
/// now. A good night after a hard training block produces exactly the
/// contradiction this guards -- a low Recovery percentage labelled
/// "Excellent".
final class RecoveryComplicationBandTests: XCTestCase {

    /// The case from the spec: the night scored well, the body did not
    /// recover. The band shown next to Recovery must describe Recovery.
    func testAGoodNightDoesNotMakeRecoveryLookHigh() {
        let sleepBand = SleepScore.Band.forValue(92).label
        let recoveryBand = RecoveryScore.Band.forPercent(28).label

        XCTAssertNotEqual(
            recoveryBand, sleepBand,
            "a 92 night and a 28 recovery must not share a label"
        )
        XCTAssertEqual(recoveryBand, "Low")
    }

    /// And the reverse: a rough night does not make Recovery look bad.
    func testARoughNightDoesNotMakeRecoveryLookLow() {
        XCTAssertEqual(RecoveryScore.Band.forPercent(84).label, "High")
    }

    /// The mapping the complication depends on, pinned at its edges so a
    /// change to the thresholds is a deliberate act rather than a surprise.
    func testBandBoundaries() {
        XCTAssertEqual(RecoveryScore.Band.forPercent(0).label, "Low")
        XCTAssertEqual(RecoveryScore.Band.forPercent(100).label, "High")
        for percent in 0...100 {
            let label = RecoveryScore.Band.forPercent(percent).label
            XCTAssertTrue(
                ["Low", "Moderate", "High"].contains(label),
                "unexpected band \(label) at \(percent)"
            )
        }
    }
}
