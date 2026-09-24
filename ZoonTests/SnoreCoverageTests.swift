import XCTest

/// Audit §8: a snore result's confidence is bounded by how much of the
/// night was heard, not only by how good the detector was.
final class SnoreCoverageTests: XCTestCase {

    private func band(
        monitored: TimeInterval,
        window: TimeInterval = 8 * 3600,
        interruptions: TimeInterval = 0,
        classifierSeconds: Double = 15,
        heuristicSeconds: Double = 12,
        classifier: Bool = true,
        ended: Bool = true
    ) -> SnoreConfidenceBreakdown {
        SnoreEpisodeAggregator.breakdown(
            classifierAvailable: classifier,
            classifierSupportsSnoring: classifier,
            monitoredSeconds: monitored,
            lastBufferAge: ended ? 9_000 : 0.3,
            heuristicSeconds: heuristicSeconds,
            classifierSeconds: classifierSeconds,
            sessionEnded: ended,
            interruptionDuration: interruptions,
            intendedWindowSeconds: window
        )
    }

    /// The audit's example.
    func testThirtyOneMinutesOfAnEightHourNightIsNotHigh() {
        let result = band(monitored: 31 * 60)
        XCTAssertEqual(result.detector, .high, "the detector itself was fine")
        XCTAssertEqual(result.coverage.confidence, .limited)
        XCTAssertEqual(result.final, .limited)
    }

    func testSevenCleanHoursOfEightCanBeHigh() {
        let result = band(monitored: 7 * 3600)
        XCTAssertEqual(result.final, .high)
        XCTAssertEqual(result.coveragePercent, 88)
    }

    func testALongInterruptionLowersCoverage() {
        let clean = band(monitored: 6.5 * 3600)
        let interrupted = band(monitored: 6.5 * 3600, interruptions: 2.5 * 3600)
        XCTAssertEqual(clean.final, .high)
        XCTAssertLessThan(interrupted.final, clean.final)
    }

    func testAFinishedSessionIsNotLimitedJustBecauseTheMicIsQuiet() {
        XCTAssertEqual(band(monitored: 7 * 3600, ended: true).final, .high)
    }

    func testTheFinalLevelIsTheWeakerOfTheTwo() {
        let noClassifier = band(monitored: 7 * 3600, classifierSeconds: 0, heuristicSeconds: 12, classifier: false)
        XCTAssertEqual(noClassifier.coverage.confidence, .high)
        XCTAssertLessThan(noClassifier.detector, .high)
        XCTAssertEqual(noClassifier.final, noClassifier.detector)
    }

    /// A quiet night is agreement, not a weaker detector.
    func testBothSilentIsAgreement() {
        XCTAssertEqual(band(monitored: 7 * 3600, classifierSeconds: 0, heuristicSeconds: 0).detector, .high)
        XCTAssertLessThan(band(monitored: 7 * 3600, classifierSeconds: 0, heuristicSeconds: 12).detector, .high,
                          "one signal firing while the other is silent is disagreement")
    }

    func testNoSnoreOnLowCoverageSaysNoConclusion() {
        let sentence = band(monitored: 40 * 60, classifierSeconds: 0, heuristicSeconds: 0).resultSentence(snoreMinutes: 0)
        XCTAssertTrue(sentence.hasPrefix("No conclusion"), sentence)
        XCTAssertFalse(sentence.lowercased().contains("no snoring flagged"), sentence)

        let covered = band(monitored: 7 * 3600, classifierSeconds: 0, heuristicSeconds: 0).resultSentence(snoreMinutes: 0)
        XCTAssertTrue(covered.hasPrefix("No snoring flagged"), covered)
    }

    func testSnoringIsNeverCalledADiagnosis() {
        let sentence = band(monitored: 7 * 3600).resultSentence(snoreMinutes: 30)
        XCTAssertFalse(DiagnosticLanguageGuard.rejects(sentence), sentence)
        XCTAssertFalse(sentence.lowercased().contains("apnea"))
    }

    func testCoverageRatioIsBounded() {
        XCTAssertEqual(SnoreCoverage(monitoredSeconds: 10 * 3600, interruptionSeconds: 0, intendedWindowSeconds: 8 * 3600).ratio, 1)
        XCTAssertEqual(SnoreCoverage(monitoredSeconds: 3600, interruptionSeconds: 0, intendedWindowSeconds: 0).ratio, 0)
    }

    // MARK: - Result card (audit §19)

    /// 31 quiet minutes used to headline "0% of the night".
    func testAShortQuietSessionHeadlinesNoConclusionNotZero() {
        let result = SnoreResultSummary(monitoredMinutes: 31, snoreMinutes: 0, coveragePercent: 6,
                                        interruptionMinutes: nil, quality: .limited)
        XCTAssertEqual(result.headline, "No conclusion")
        XCTAssertFalse(result.isConclusive)
        XCTAssertFalse(result.headline.contains("0%"))
    }

    func testAWellCoveredQuietNightSaysNoneFlagged() {
        let result = SnoreResultSummary(monitoredMinutes: 420, snoreMinutes: 0, coveragePercent: 88,
                                        interruptionMinutes: 0, quality: .high)
        XCTAssertEqual(result.headline, "None flagged")
        XCTAssertTrue(result.isConclusive)
    }

    /// The percentage names what it is a share of.
    func testSnoringIsAShareOfMonitoredTime() {
        let result = SnoreResultSummary(monitoredMinutes: 400, snoreMinutes: 48, coveragePercent: 83,
                                        interruptionMinutes: 12, quality: .moderate)
        XCTAssertEqual(result.headline, "12% of monitored time")
        XCTAssertEqual(result.rows.map(\.label), ["Monitored", "Planned night covered", "Interrupted", "Monitoring quality", "Flagged"])
        XCTAssertEqual(result.rows.map(\.value), ["6 h 40 min", "83%", "12 min", "Moderate", "48 min"])
    }

    /// Summaries stored before coverage existed show what they have.
    func testAnOlderSummaryShowsOnlyWhatItStored() {
        let result = SnoreResultSummary(monitoredMinutes: 360, snoreMinutes: 0, coveragePercent: nil,
                                        interruptionMinutes: nil, quality: nil)
        XCTAssertEqual(result.rows.map(\.label), ["Monitored"])
        XCTAssertEqual(result.headline, "None flagged")
    }

    func testDurations() {
        XCTAssertEqual(SnoreResultSummary.duration(45), "45 min")
        XCTAssertEqual(SnoreResultSummary.duration(60), "1 h")
        XCTAssertEqual(SnoreResultSummary.duration(425), "7 h 5 min")
        XCTAssertEqual(SnoreResultSummary.duration(-3), "0 min")
    }
}
