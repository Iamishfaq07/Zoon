import XCTest

final class LightCoachTests: XCTestCase {

    func testMorningWindowWithoutDaylightDataGivesGenericAdvice() {
        let wakeTime = Date()
        let now = wakeTime.addingTimeInterval(30 * 60)
        let guidance = LightCoach.guidance(wakeTime: wakeTime, onsetHour: nil, now: now)
        XCTAssertEqual(guidance?.headline, "Get outside if you can")
    }

    func testMorningWindowWithLowDaylightStillGivesGenericAdvice() {
        let wakeTime = Date()
        let now = wakeTime.addingTimeInterval(30 * 60)
        let guidance = LightCoach.guidance(
            wakeTime: wakeTime, onsetHour: nil, todayDaylightMinutes: 5, now: now
        )
        XCTAssertEqual(guidance?.headline, "Get outside if you can")
    }

    func testMorningWindowWithMeaningfulDaylightAcknowledgesIt() {
        let wakeTime = Date()
        let now = wakeTime.addingTimeInterval(30 * 60)
        let guidance = LightCoach.guidance(
            wakeTime: wakeTime, onsetHour: nil, todayDaylightMinutes: 20, now: now
        )
        XCTAssertEqual(guidance?.headline, "You've already gotten some daylight")
        XCTAssertTrue(guidance?.detail.contains("20") ?? false)
    }

    func testExactlyAtThresholdCountsAsMeaningful() {
        let wakeTime = Date()
        let now = wakeTime.addingTimeInterval(30 * 60)
        let guidance = LightCoach.guidance(
            wakeTime: wakeTime, onsetHour: nil,
            todayDaylightMinutes: LightCoach.meaningfulDaylightMinutes, now: now
        )
        XCTAssertEqual(guidance?.headline, "You've already gotten some daylight")
    }

    func testOutsideMorningWindowIgnoresDaylightMinutes() {
        let wakeTime = Date()
        let now = wakeTime.addingTimeInterval(4 * 3600)
        let guidance = LightCoach.guidance(
            wakeTime: wakeTime, onsetHour: nil, todayDaylightMinutes: 40, now: now
        )
        XCTAssertNil(guidance)
    }
}
