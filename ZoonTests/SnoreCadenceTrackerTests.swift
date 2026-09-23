import XCTest

final class SnoreCadenceTrackerTests: XCTestCase {

    func testFiveSecondCadenceCountsAsSnoring() {
        var tracker = SnoreCadenceTracker()
        for t in stride(from: 0.0, through: 15.0, by: 5.0) {
            tracker.registerBurst(at: t)
        }
        XCTAssertTrue(tracker.isSnoring(at: 15), "5s cadence must survive an 18s window")
    }

    func testTwoSecondCadenceCountsAsSnoring() {
        var tracker = SnoreCadenceTracker()
        for t in stride(from: 0.0, through: 8.0, by: 2.0) {
            tracker.registerBurst(at: t)
        }
        XCTAssertTrue(tracker.isSnoring(at: 8))
    }

    func testSixSecondCadenceCountsAsSnoring() {
        var tracker = SnoreCadenceTracker()
        for t in [0.0, 6.0, 12.0, 18.0] {
            tracker.registerBurst(at: t)
        }
        XCTAssertTrue(tracker.isSnoring(at: 18))
    }

    func testASingleCoughIsNotSnoring() {
        var tracker = SnoreCadenceTracker()
        tracker.registerBurst(at: 0)
        XCTAssertFalse(tracker.isSnoring(at: 1))
    }

    func testASustainedBreakResetsTheRun() {
        var tracker = SnoreCadenceTracker()
        tracker.registerBurst(at: 0)
        tracker.registerBurst(at: 4)
        tracker.registerBurst(at: 20)
        XCTAssertFalse(tracker.isSnoring(at: 20))
    }

    func testTheOldSixSecondWindowCouldNotSeeAFiveSecondCadence() {
        var short = SnoreCadenceTracker(historyWindow: 6)
        for t in [0.0, 5.0, 10.0] {
            short.registerBurst(at: t)
        }
        XCTAssertFalse(short.isSnoring(at: 10), "documents the shipped cadence bug")
    }
}
