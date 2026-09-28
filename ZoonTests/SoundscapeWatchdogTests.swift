import XCTest

/// The Sleep Sounds watchdog restarts a graph that has gone silent. It used
/// to be allowed once per playback, so a second, unrelated stall later in
/// the night left the rest of it silent.
final class SoundscapeWatchdogTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testTheFirstStallIsAlwaysRecovered() {
        XCTAssertTrue(WatchdogRecoveryPolicy.mayRecover(lastRecoveryAt: nil, lastHealthyAt: t0))
    }

    /// Three hours of healthy playback after a recovery: a new stall is a
    /// new problem, not a loop.
    func testALaterStallAfterHealthyPlaybackIsRecoveredToo() {
        let recovered = t0
        let healthyUntil = t0.addingTimeInterval(3 * 3600)
        XCTAssertTrue(WatchdogRecoveryPolicy.mayRecover(lastRecoveryAt: recovered, lastHealthyAt: healthyUntil))
    }

    /// Silent again straight after a restart: the graph will not stay up, and
    /// the watchdog stops trying rather than loop all night.
    func testAStallStraightAfterARecoveryGivesUp() {
        XCTAssertFalse(WatchdogRecoveryPolicy.mayRecover(lastRecoveryAt: t0, lastHealthyAt: t0.addingTimeInterval(8)))
        XCTAssertFalse(WatchdogRecoveryPolicy.mayRecover(lastRecoveryAt: t0, lastHealthyAt: t0))
    }

    func testTheThresholdIsAMinuteOfHealthyPlayback() {
        let recovered = t0
        let edge = t0.addingTimeInterval(WatchdogRecoveryPolicy.healthyIntervalBeforeAnotherRecovery)
        XCTAssertTrue(WatchdogRecoveryPolicy.mayRecover(lastRecoveryAt: recovered, lastHealthyAt: edge))
        XCTAssertFalse(WatchdogRecoveryPolicy.mayRecover(lastRecoveryAt: recovered, lastHealthyAt: edge.addingTimeInterval(-1)))
    }
}
