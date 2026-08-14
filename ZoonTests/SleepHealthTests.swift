import XCTest

final class SleepHealthTests: XCTestCase {

    func testInsufficientNightsReturnsNilScore() {
        let nights = Fixture.consecutiveNights(3)
        let health = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: nights)
        XCTAssertNil(health.score)
        XCTAssertTrue(health.components.isEmpty)
        XCTAssertEqual(health.confidence, .insufficient)
    }

    func testFiltersToTheRequestedWindow() {
        // 30 consecutive nights, but only ones inside the 14-day window
        // should count toward nightCount.
        let nights = Fixture.consecutiveNights(30)
        let health = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: nights)
        XCTAssertLessThanOrEqual(health.nightCount, 14)
    }

    func testGoodNightsScoreHigh() {
        let nights = Fixture.consecutiveNights(14, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: 470, timeInBedMinutes: 490, wakeCount: 1, breathingDisturbances: 0.2)
        })
        let health = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: nights)
        guard let score = health.score else {
            return XCTFail("expected a score")
        }
        XCTAssertGreaterThan(score, 70)
        XCTAssertEqual(health.band, .solid)
    }

    func testShortSleepAndFragmentedNightsScoreLower() {
        let goodNights = Fixture.consecutiveNights(14, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: 470, timeInBedMinutes: 490, wakeCount: 1)
        })
        let goodHealth = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: goodNights)

        let poorNights = Fixture.consecutiveNights(14, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: 320, timeInBedMinutes: 420, wakeCount: 8)
        })
        let poorHealth = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: poorNights)

        guard let goodScore = goodHealth.score, let poorScore = poorHealth.score else {
            return XCTFail("expected both to produce a score")
        }
        XCTAssertGreaterThan(goodScore, poorScore)
    }

    func testMissingBreathingDataOmitsThatComponent() {
        let nights = Fixture.consecutiveNights(14, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, breathingDisturbances: nil)
        })
        let health = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: nights)
        XCTAssertFalse(health.components.contains { $0.id == "breathing" })
    }

    func testMorningFeelingAddsRestfulnessComponent() {
        let nights = Fixture.consecutiveNights(14)
        let withoutFeelings = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: nights)
        XCTAssertFalse(withoutFeelings.components.contains { $0.id == "restfulness" })

        let withFeelings = SleepHealth.compute(
            window: .twoWeeks, goalMinutes: 480, nights: nights,
            morningFeelingRawValues: [4, 5, 4, 5, 3]
        )
        XCTAssertTrue(withFeelings.components.contains { $0.id == "restfulness" })
    }

    func testComponentScoresAreOrientedHigherIsBetter() {
        let nights = Fixture.consecutiveNights(14, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: 470, timeInBedMinutes: 490, wakeCount: 0, breathingDisturbances: 0)
        })
        let health = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: nights)
        for component in health.components {
            XCTAssertGreaterThanOrEqual(component.score, 0)
            XCTAssertLessThanOrEqual(component.score, 100)
        }
    }
}
