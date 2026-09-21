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
}
