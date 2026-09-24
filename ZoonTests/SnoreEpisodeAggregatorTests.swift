import XCTest

final class SnoreEpisodeAggregatorTests: XCTestCase {

    func testOverlappingSnoringWindowsMergeIntoOneDuration() {
        let windows = [
            SnoreClassificationWindow(start: 0, duration: 1.2, confidence: 0.8, identifier: "snoring"),
            SnoreClassificationWindow(start: 0.8, duration: 1.2, confidence: 0.7, identifier: "snoring"),
            SnoreClassificationWindow(start: 10, duration: 2, confidence: 0.9, identifier: "snoring")
        ]
        let seconds = SnoreEpisodeAggregator.snoreSeconds(from: windows)
        XCTAssertEqual(seconds, 2.0 + 2.0, accuracy: 0.05)
    }

    func testLowConfidenceWindowsAreIgnored() {
        let windows = [
            SnoreClassificationWindow(start: 0, duration: 4, confidence: 0.2, identifier: "snoring")
        ]
        XCTAssertEqual(SnoreEpisodeAggregator.snoreSeconds(from: windows), 0)
    }

    func testCoughWindowsDoNotAddSnoreSeconds() {
        let windows = [
            SnoreClassificationWindow(start: 0, duration: 3, confidence: 0.9, identifier: "coughing")
        ]
        XCTAssertEqual(SnoreEpisodeAggregator.snoreSeconds(from: windows), 0)
    }

    func testConfidenceIsLimitedWithoutAClassifier() {
        let band = SnoreEpisodeAggregator.confidence(
            classifierAvailable: false,
            classifierSupportsSnoring: false,
            monitoredSeconds: 60,
            lastBufferAge: 0.2,
            heuristicSeconds: 5,
            classifierSeconds: 0
        )
        XCTAssertEqual(band, .limited)
    }

    /// Was 40 minutes -- which is the §8 defect: a sliver of the night read
    /// as strong. Coverage now has to be most of the night too.
    func testHighConfidenceNeedsAgreementAndCoverage() {
        let band = SnoreEpisodeAggregator.confidence(
            classifierAvailable: true,
            classifierSupportsSnoring: true,
            monitoredSeconds: 7 * 3600,
            lastBufferAge: 0.4,
            heuristicSeconds: 12,
            classifierSeconds: 15
        )
        XCTAssertEqual(band, .high)
    }

    func testCompletedSessionDoesNotBecomeLimitedBecauseTheMicWentQuiet() {
        let band = SnoreEpisodeAggregator.confidence(
            classifierAvailable: true,
            classifierSupportsSnoring: true,
            monitoredSeconds: 7 * 3600,
            lastBufferAge: 8_000,
            heuristicSeconds: 12,
            classifierSeconds: 15,
            sessionEnded: true
        )
        XCTAssertNotEqual(band, .limited)
    }
}
