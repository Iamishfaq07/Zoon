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
}
