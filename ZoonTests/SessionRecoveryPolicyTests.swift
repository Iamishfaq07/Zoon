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

    // MARK: - Interruption resume (audit §9.3)

    private struct ActivationFailed: Error {}

    @MainActor
    func testOwnersAreNotResumedWhenActivationNeverSucceeds() async {
        var attempts = 0
        var notified = false
        let resumed = await InterruptionResumePolicy.resume(
            sleep: { _ in },
            activate: { attempts += 1; throw ActivationFailed() },
            notify: { notified = true }
        )
        XCTAssertFalse(resumed)
        XCTAssertFalse(notified, "owners must not be told to resume on a dead session")
        XCTAssertEqual(attempts, InterruptionResumePolicy.attemptDelays.count, "bounded, not forever")
    }

    @MainActor
    func testALateSuccessResumesOnceAfterActivation() async {
        var attempts = 0
        var notifications = 0
        var slept: [TimeInterval] = []
        let resumed = await InterruptionResumePolicy.resume(
            sleep: { slept.append($0) },
            activate: {
                attempts += 1
                if attempts < 3 { throw ActivationFailed() }
            },
            notify: { notifications += 1 }
        )
        XCTAssertTrue(resumed)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(slept, [0.5, 1.5], "backoff between attempts")
    }

    @MainActor
    func testANewInterruptionStopsTheRetries() async {
        var attempts = 0
        var notified = false
        let resumed = await InterruptionResumePolicy.resume(
            sleep: { _ in },
            shouldContinue: { attempts == 0 },
            activate: { attempts += 1; throw ActivationFailed() },
            notify: { notified = true }
        )
        XCTAssertFalse(resumed)
        XCTAssertFalse(notified)
        XCTAssertEqual(attempts, 1)
    }
}
