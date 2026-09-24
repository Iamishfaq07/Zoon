import XCTest

final class ReviewPromptTests: XCTestCase {

    private func night(asleep: Double, need: Double? = 480) -> SleepNightFeatures {
        var night = Fixture.night(daysAgo: 0, timeAsleepMinutes: asleep)
        night.sleepNeedBaselineMinutes = need
        return night
    }

    func testAsksAfterAFullNightOnceThereAreTwoWeeks() {
        XCTAssertTrue(ReviewPrompt.shouldAsk(nightsRecorded: 14, lastNight: night(asleep: 470), currentVersion: "1.2", lastAskedVersion: nil))
    }

    func testNotBeforeTwoWeeks() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(nightsRecorded: 13, lastNight: night(asleep: 500), currentVersion: "1.2", lastAskedVersion: nil))
    }

    func testNotAfterAShortNight() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(nightsRecorded: 30, lastNight: night(asleep: 400), currentVersion: "1.2", lastAskedVersion: nil))
    }

    func testNotWhenTheNeedIsUnknown() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(nightsRecorded: 30, lastNight: night(asleep: 500, need: nil), currentVersion: "1.2", lastAskedVersion: nil))
    }

    func testOncePerVersion() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(nightsRecorded: 30, lastNight: night(asleep: 500), currentVersion: "1.2", lastAskedVersion: "1.2"))
        XCTAssertTrue(ReviewPrompt.shouldAsk(nightsRecorded: 30, lastNight: night(asleep: 500), currentVersion: "1.3", lastAskedVersion: "1.2"))
    }
}
