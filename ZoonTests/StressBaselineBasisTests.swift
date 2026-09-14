import XCTest

/// Which baseline a load reading was measured against, and why it matters.
final class StressBaselineBasisTests: XCTestCase {

    private func score(
        hr: Double?,
        overnightHR: Double?,
        wakingHR: Double?,
        baselineNightCount: Int = 30
    ) -> StressScore? {
        StressScore.compute(
            avgHeartRate: hr,
            avgHRV: nil,
            hrBaseline: overnightHR,
            hrvBaseline: nil,
            sampledMinutes: 240,
            baselineNightCount: baselineNightCount,
            wakingHRBaseline: wakingHR
        )
    }

    /// The defect, stated as a test. A calm desk-bound 70 against a normal
    /// sleeping 54 is +30%, which the ±20% band pushes to the top.
    func testACalmWakingHeartRateReadsHighAgainstASleepingBaseline() throws {
        let overnight = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: nil))
        XCTAssertEqual(overnight.band, .high, "this is the behaviour being fixed, not an endorsement")
        XCTAssertEqual(overnight.hrBasis, .overnightResting)
        XCTAssertFalse(overnight.isScaleMatched)
    }

    /// The same reading against this person's own waking readings from this
    /// hour is exactly typical.
    func testTheSameReadingIsCalmAgainstAWakingBaseline() throws {
        let waking = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: 70))
        XCTAssertEqual(waking.band, .calm)
        XCTAssertEqual(waking.hrBasis, .wakingTimeOfDay)
        XCTAssertTrue(waking.isScaleMatched)
    }

    func testTheWakingBaselineWinsWhereverItExists() throws {
        let score = try XCTUnwrap(score(hr: 82, overnightHR: 54, wakingHR: 70))
        XCTAssertEqual(score.hrBaseline, 70, "the overnight figure must not silently take over")
    }

    func testTheOvernightBaselineIsStillUsedWhenThereIsNoWakingOne() throws {
        let score = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: nil))
        XCTAssertEqual(score.hrBaseline, 54, "a worse comparison beats no comparison")
    }

    func testNoBaselineAtAllIsStillNoScore() {
        XCTAssertNil(score(hr: 70, overnightHR: nil, wakingHR: nil))
    }

    /// A waking baseline stands on its own history, so a thin *night* count
    /// says nothing about it.
    func testAThinNightCountDoesNotMakeAWakingComparisonAnEstimate() throws {
        let waking = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: 70, baselineNightCount: 2))
        XCTAssertFalse(waking.isEstimate)

        let overnight = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: nil, baselineNightCount: 2))
        XCTAssertTrue(overnight.isEstimate)
    }

    // MARK: - Disclosure

    func testTheNoteNamesWhatWasActuallyCompared() throws {
        let waking = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: 70))
        XCTAssertTrue(waking.baselineContextNote.lowercased().contains("waking"))
        XCTAssertFalse(waking.baselineContextNote.lowercased().contains("overnight"))

        let overnight = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: nil))
        XCTAssertTrue(overnight.baselineContextNote.lowercased().contains("overnight"))
    }

    // MARK: - The label follows the fact

    /// A caveat that outlives its own cause stops being read. The
    /// Experimental label had exactly one stated reason -- the scale
    /// mismatch -- so it has to be able to come off when that is gone.
    func testExperimentalComesOffOnceTheComparisonIsLikeForLike() throws {
        let waking = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: 70))
        XCTAssertNil(waking.experimentalReason)
    }

    func testExperimentalStaysWhileTheWakingBaselineIsNotReady() throws {
        let overnight = try XCTUnwrap(score(hr: 70, overnightHR: 54, wakingHR: nil))
        let reason = try XCTUnwrap(overnight.experimentalReason)
        XCTAssertTrue(reason.lowercased().contains("overnight"), "the label must say why it is there")
    }

    /// One of each is the awkward case, and it must not claim to be either.
    func testAMixedComparisonSaysSo() throws {
        let mixed = try XCTUnwrap(
            StressScore.compute(
                avgHeartRate: 70,
                avgHRV: 40,
                hrBaseline: 54,
                hrvBaseline: 60,
                sampledMinutes: 240,
                baselineNightCount: 30,
                wakingHRBaseline: 70,
                wakingHRVBaseline: nil
            )
        )
        XCTAssertFalse(mixed.isScaleMatched)
        XCTAssertTrue(mixed.baselineContextNote.lowercased().contains("partly"))
        XCTAssertNotNil(
            mixed.experimentalReason,
            "half a fix is not a fix -- the label stays until every component is matched"
        )
    }
}
