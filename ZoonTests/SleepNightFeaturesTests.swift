import XCTest

final class SleepNightFeaturesTests: XCTestCase {

    func testTotal24hAsleepMinutesAddsSecondaryToMain() {
        var night = Fixture.night(timeAsleepMinutes: 400)
        night.secondaryAsleepMinutes = 45
        XCTAssertEqual(night.total24hAsleepMinutes, 445, accuracy: 0.01)
    }

    func testTotal24hAsleepMinutesDefaultsToMainSleepAlone() {
        let night = Fixture.night(timeAsleepMinutes: 400)
        XCTAssertEqual(night.total24hAsleepMinutes, 400, accuracy: 0.01)
    }
}
