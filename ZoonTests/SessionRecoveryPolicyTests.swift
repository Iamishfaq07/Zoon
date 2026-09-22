import XCTest

final class SessionRecoveryPolicyTests: XCTestCase {

    func testOwnersAreNotToldTheSessionIsHealthyWhenRestoreFailed() {
        XCTAssertFalse(AudioSessionResetOrder.shouldNotifyOwners(sessionRestored: false))
        XCTAssertTrue(AudioSessionResetOrder.shouldNotifyOwners(sessionRestored: true))
    }

    func testAFailedEngineStartLeavesTheGapOpen() {
        XCTAssertFalse(SnoreResumePolicy.shouldCloseGap(engineStarted: false, receivedBuffer: false))
        XCTAssertFalse(SnoreResumePolicy.shouldCloseGap(engineStarted: true, receivedBuffer: false))
        XCTAssertFalse(SnoreResumePolicy.shouldCloseGap(engineStarted: false, receivedBuffer: true))
    }

    func testFirstValidBufferAfterASuccessfulStartClosesTheGap() {
        XCTAssertTrue(SnoreResumePolicy.shouldCloseGap(engineStarted: true, receivedBuffer: true))
    }
}
