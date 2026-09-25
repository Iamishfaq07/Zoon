import XCTest

final class DeepLinkTests: XCTestCase {

    override func tearDown() {
        DeepLink.clear()
    }

    func testPendingNapMinutesAreConsumedOnce() {
        DeepLink.pendingNapMinutes = 20
        XCTAssertEqual(DeepLink.consumeNapMinutes(), 20)
        XCTAssertNil(DeepLink.consumeNapMinutes())
    }

    func testZeroMinutesDoNotCountAsAPendingNap() {
        DeepLink.pendingNapMinutes = 0
        XCTAssertNil(DeepLink.pendingNapMinutes)
    }

    func testPendingSoundIsConsumedOnce() {
        DeepLink.pendingSound = "rain"
        XCTAssertEqual(DeepLink.consumeSound(), "rain")
        XCTAssertNil(DeepLink.consumeSound())
    }

    func testTheWindDownStartIsConsumedOnce() {
        DeepLink.pendingStartsWindDown = true
        XCTAssertTrue(DeepLink.consumeStartsWindDown())
        XCTAssertFalse(DeepLink.consumeStartsWindDown(), "a leftover flag must not start a routine on a later launch")
    }

    func testClearDropsAPendingWindDownStart() {
        DeepLink.pendingStartsWindDown = true
        DeepLink.clear()
        XCTAssertFalse(DeepLink.pendingStartsWindDown)
    }

    func testTheWindDownScreenBelongsToTheSleepTab() {
        XCTAssertEqual(DeepLink.Destination.windDown.tab, "sleep")
    }
}
