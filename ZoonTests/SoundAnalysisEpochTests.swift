import XCTest

final class SoundAnalysisEpochTests: XCTestCase {

    func testLocalClassifierTimeMapsOntoSessionTime() {
        let epoch = SoundAnalysisEpoch(sessionElapsedAtStart: 120, wallClockStart: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(epoch.sessionTime(local: 30), 150)
        XCTAssertEqual(epoch.date(local: 30).timeIntervalSince1970, 1_030)
    }

    func testARebuiltAnalyzerDoesNotLandOnTheFirstMinute() {
        let first = SoundAnalysisEpoch(sessionElapsedAtStart: 0, wallClockStart: Date(timeIntervalSince1970: 0))
        let afterCall = SoundAnalysisEpoch(sessionElapsedAtStart: 3_600, wallClockStart: Date(timeIntervalSince1970: 3_600))
        XCTAssertEqual(first.sessionTime(local: 120), 120)
        XCTAssertEqual(afterCall.sessionTime(local: 30), 3_630)
        XCTAssertGreaterThan(afterCall.sessionTime(local: 0), first.sessionTime(local: 120))
    }

    /// Session elapsed 2h, then a 20-minute call. The new analyzer starts at
    /// 01:20, not 01:00. Using start + elapsed as wall-clock would put the
    /// first post-call event twenty minutes too early.
    func testWallClockAfterALongInterruptionIsNowNotElapsed() {
        let sessionStart = Date(timeIntervalSince1970: 0) // 23:00 in the prompt's story
        let monitored: TimeInterval = 7_200
        let gap: TimeInterval = 1_200
        let resume = sessionStart.addingTimeInterval(monitored + gap)
        let epoch = SoundAnalysisEpoch.beginningNow(sessionElapsed: monitored, now: resume)
        XCTAssertEqual(epoch.sessionTime(local: 30), 7_230)
        XCTAssertEqual(epoch.date(local: 30).timeIntervalSince(sessionStart), 7_200 + 1_200 + 30)
        XCTAssertNotEqual(
            epoch.date(local: 30).timeIntervalSince(sessionStart),
            monitored + 30,
            "must not collapse wall-clock onto session elapsed"
        )
    }
}
