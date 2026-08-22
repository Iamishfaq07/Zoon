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
        XCTAssertTrue(health.band == .solid || health.band == .strong)
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

        let checkIns = [0, 1, 2, 3, 4].map { daysAgo in
            SleepHealth.DatedMorningCheckIn(
                date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
                feeling: 4
            )
        }
        let withFeelings = SleepHealth.compute(
            window: .twoWeeks, goalMinutes: 480, nights: nights,
            morningCheckIns: checkIns
        )
        XCTAssertTrue(withFeelings.components.contains { $0.id == "restfulness" })
    }

    /// The actual bug: `compute` used to filter with a lower cutoff only,
    /// so a second call with `now` shifted back (the "previous period"
    /// pattern `InsightsHero` uses) still let every night up to the real
    /// present through -- the previous window was never actually bounded
    /// above, so it silently swallowed the current window too.
    func testCurrentAndPreviousWindowsDoNotOverlap() {
        // 60 nights of steadily improving sleep, oldest first, so the two
        // 30-day windows are numerically distinguishable if -- and only
        // if -- they're actually scoped to different nights.
        let nights = Fixture.consecutiveNights(60, template: { daysAgo in
            // daysAgo counts down from 60 to 1 as nights get more recent;
            // more recent nights sleep longer.
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: 300 + Double(60 - daysAgo) * 3)
        })

        let current = SleepHealth.compute(window: .month, goalMinutes: 480, nights: nights)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let previous = SleepHealth.compute(window: .month, goalMinutes: 480, nights: nights, now: cutoff)

        XCTAssertEqual(current.nightCount, 30)
        XCTAssertEqual(previous.nightCount, 30)
        guard let currentScore = current.score, let previousScore = previous.score else {
            return XCTFail("expected both windows to produce a score")
        }
        // The later window slept more every night by construction; if the
        // windows overlapped (the bug), both computations would draw from
        // largely the same nights and the scores would land close together.
        XCTAssertGreaterThan(currentScore, previousScore)
    }

    func testFiveComponentsAtMinimumNightsIsNotHighConfidence() {
        // Exactly the failure case the spec calls out: enough components,
        // barely enough nights, no check-ins logged.
        let nights = Fixture.consecutiveNights(7, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: 470, timeInBedMinutes: 490, wakeCount: 1, breathingDisturbances: 0.2)
        })
        let health = SleepHealth.compute(window: .twoWeeks, goalMinutes: 480, nights: nights)
        XCTAssertNotEqual(health.confidence, .high)
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
