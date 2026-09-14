import XCTest

/// Today's "right now" line is about the live reading; the ring above it is
/// about the night that ended. These pin the pieces that line is built from,
/// so the two cannot quietly merge back into one claim.
final class RightNowCompositionTests: XCTestCase {

    private func load(hr: Double, wakingBaseline: Double?) -> StressScore? {
        StressScore.compute(
            avgHeartRate: hr,
            avgHRV: nil,
            hrBaseline: 54,
            hrvBaseline: nil,
            sampledMinutes: 240,
            baselineNightCount: 30,
            wakingHRBaseline: wakingBaseline
        )
    }

    /// Morning Recovery must keep saying it is about the morning. The empty
    /// state of the "right now" line leans on this string, and the previous
    /// copy there described the morning figure as something that changes
    /// during the day.
    func testTheMorningFigureStillDeclaresItsTiming() {
        let note = RecoveryPresentationState.timingNote.lowercased()
        XCTAssertTrue(note.contains("last night"))
        XCTAssertTrue(note.contains("doesn't move") || note.contains("does not move"))
    }

    func testEveryLoadBandHasAWordForTheLine() {
        for band in [StressScore.Band.calm, .elevated, .high] {
            XCTAssertFalse(band.label.isEmpty)
            XCTAssertFalse(band.detail.isEmpty)
        }
    }

    /// The line states the basis beside the band, so "calm" is never read as
    /// a verdict without saying what it was calm *against*.
    func testTheLineCanAlwaysSayWhatItComparedAgainst() throws {
        let waking = try XCTUnwrap(load(hr: 70, wakingBaseline: 70))
        XCTAssertFalse(waking.baselineContextNote.isEmpty)
        XCTAssertTrue(waking.isScaleMatched)

        let fallback = try XCTUnwrap(load(hr: 70, wakingBaseline: nil))
        XCTAssertFalse(fallback.baselineContextNote.isEmpty)
        XCTAssertFalse(fallback.isScaleMatched)
    }

    /// No live score is a real state with its own sentence, not a reason to
    /// describe the morning number differently.
    func testNoLiveReadingIsRepresentable() {
        XCTAssertNil(
            StressScore.compute(
                avgHeartRate: nil,
                avgHRV: nil,
                hrBaseline: 54,
                hrvBaseline: 60,
                sampledMinutes: 0,
                baselineNightCount: 30
            ),
            "with no live sample there is no load score, and the line says so"
        )
    }
}
