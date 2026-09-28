import XCTest

/// Snore Check when Apple's classifier stops mid-session, and which night a
/// session is filed under.
///
/// SoundAnalysis stops a request for good after an error, and on some iOS
/// versions the built-in classifier fails once the phone locks. The heuristic
/// keeps listening, but silence from a classifier that was not running is not
/// agreement, so a quiet night it missed must not read "Strong / None flagged".
final class SnoreClassifierOutageTests: XCTestCase {

    private func detector(
        share: Double,
        classifierSeconds: Double = 0,
        heuristicSeconds: Double = 0
    ) -> SnoreMonitoringConfidence {
        SnoreEpisodeAggregator.detectorConfidence(
            classifierAvailable: true,
            classifierSupportsSnoring: true,
            monitoredSeconds: 7 * 3600,
            lastBufferAge: nil,
            heuristicSeconds: heuristicSeconds,
            classifierSeconds: classifierSeconds,
            sessionEnded: true,
            classifierActiveShare: share
        )
    }

    func testAQuietNightTheClassifierHeardInFullIsStrong() {
        XCTAssertEqual(detector(share: 1), .high)
    }

    func testTheDefaultKeepsTheOldBehaviour() {
        let old = SnoreEpisodeAggregator.detectorConfidence(
            classifierAvailable: true,
            classifierSupportsSnoring: true,
            monitoredSeconds: 7 * 3600,
            lastBufferAge: nil,
            heuristicSeconds: 0,
            classifierSeconds: 0,
            sessionEnded: true
        )
        XCTAssertEqual(old, .high)
    }

    func testAClassifierThatMissedPartOfTheNightCannotMakeItStrong() {
        XCTAssertEqual(detector(share: 0.7), .moderate)
    }

    /// Stopped at lock and never restarted: the night is judged as if there
    /// were no classifier, which is the "No conclusion" path for a quiet one.
    func testAClassifierThatMissedMostOfTheNightIsLimited() {
        XCTAssertEqual(detector(share: 0.2), .limited)
        let result = SnoreEpisodeAggregator.breakdown(
            classifierAvailable: true,
            classifierSupportsSnoring: true,
            monitoredSeconds: 7 * 3600,
            lastBufferAge: nil,
            heuristicSeconds: 0,
            classifierSeconds: 0,
            sessionEnded: true,
            intendedWindowSeconds: 8 * 3600,
            classifierActiveShare: 0.2
        )
        XCTAssertEqual(result.final, .limited)
    }

    func testTheLoudnessPatternStillCountsWhenTheClassifierWasOut() {
        XCTAssertEqual(detector(share: 0.2, heuristicSeconds: 600), .moderate)
    }

    // MARK: - Night identity

    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!

    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kolkata
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testAnEveningStartBelongsToTheNightEndingNextMorning() {
        XCTAssertEqual(SnoreNight.key(forSessionStartedAt: instant(2026, 9, 20, 23, 10), in: kolkata),
                       "2026-09-21@Asia/Kolkata")
    }

    func testAnAfterMidnightStartBelongsToTheNightEndingThatMorning() {
        XCTAssertEqual(SnoreNight.key(forSessionStartedAt: instant(2026, 9, 21, 1, 30), in: kolkata),
                       "2026-09-21@Asia/Kolkata")
    }

    /// Stopping at 23:50 used to file a short session on the night before.
    func testASessionStartedAndStoppedBeforeMidnightIsTheNightAhead() {
        XCTAssertEqual(SnoreNight.key(forSessionStartedAt: instant(2026, 9, 20, 22, 0), in: kolkata),
                       "2026-09-21@Asia/Kolkata")
    }
}
