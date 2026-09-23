import XCTest

final class SoundscapeTimerPolicyTests: XCTestCase {

    func testOffStaysOffAcrossASoundSwitch() {
        XCTAssertNil(SoundscapeTimerPolicy.deadlineAfterSwitchingSound(currentDeadline: nil))
    }

    func testAnActiveTimerIsInherited() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let deadline = now.addingTimeInterval(8 * 60)
        let kept = SoundscapeTimerPolicy.deadlineAfterSwitchingSound(currentDeadline: deadline, now: now)
        XCTAssertEqual(kept, deadline)
        XCTAssertEqual(SoundscapeTimerPolicy.remainingSeconds(deadline: kept, now: now), 8 * 60)
    }

    func testANearlyExpiredTimerDoesNotFollowTheNextSound() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let deadline = now.addingTimeInterval(8)
        XCTAssertNil(SoundscapeTimerPolicy.deadlineAfterSwitchingSound(currentDeadline: deadline, now: now))
    }

    func testStopsInCopyDoesNotHideTheInheritedTimer() {
        XCTAssertEqual(SoundscapeTimerPolicy.stopsInCopy(seconds: 134), "Stops in 2:14")
        XCTAssertEqual(SoundscapeTimerPolicy.formattedRemaining(seconds: 0), "0:00")
    }
}
