import XCTest

/// `SleepIntelligenceScore` already implemented "exclude when nil, renormalize
/// among what's present" correctly for its own components -- these tests
/// pin that contract down, particularly for `regularityIndex`, since the real
/// bug this session was one level up: `DayContextBuilder` handing this
/// function a hardcoded 0 instead of nil when regularity hadn't been measured
/// long enough yet. See `SleepRegularityTests`.
final class SleepIntelligenceScoreTests: XCTestCase {

    func testMissingRegularityIsExcludedFromComponents() {
        let history = Fixture.consecutiveNights(10)
        let night = Fixture.night(daysAgo: 0)

        let score = SleepIntelligenceScore.compute(.init(
            night: night, history: history, sleepNeedMinutes: 450,
            regularityIndex: nil, habitualMidpointHours: nil
        ))

        XCTAssertFalse(score.components.contains { $0.label == "Regularity" })
    }

    func testProvidedRegularityIsIncludedAndWeighted() {
        let history = Fixture.consecutiveNights(10)
        let night = Fixture.night(daysAgo: 0)

        let score = SleepIntelligenceScore.compute(.init(
            night: night, history: history, sleepNeedMinutes: 450,
            regularityIndex: 85, habitualMidpointHours: nil
        ))

        let regularity = score.components.first { $0.label == "Regularity" }
        XCTAssertNotNil(regularity)
        XCTAssertGreaterThan(regularity!.weightUsed, 0)
    }

    /// Every included component's `weightUsed` (the renormalized share) must
    /// sum to 1 -- otherwise the score isn't actually reconstructible from
    /// its own displayed breakdown, which is the whole point of exposing it.
    func testComponentWeightsSumToOne() {
        let history = Fixture.consecutiveNights(10)
        let night = Fixture.night(daysAgo: 0)

        let score = SleepIntelligenceScore.compute(.init(
            night: night, history: history, sleepNeedMinutes: 450,
            regularityIndex: 85, habitualMidpointHours: -0.5
        ))

        let totalWeight = score.components.reduce(0.0) { $0 + $1.weightUsed }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.0001)
    }

    func testScoreIsClampedToValidRange() {
        // An empty history plus a rock-bottom night shouldn't ever produce
        // an out-of-range percent even at the extremes.
        let terribleNight = Fixture.night(
            timeAsleepMinutes: 90, timeInBedMinutes: 300,
            avgHRV: 10, restingHeartRate: 90, avgRespiratoryRate: 25,
            wakeCount: 15
        )
        let score = SleepIntelligenceScore.compute(.init(
            night: terribleNight, history: [], sleepNeedMinutes: 480,
            regularityIndex: 5, habitualMidpointHours: nil
        ))

        XCTAssertGreaterThanOrEqual(score.percent, 0)
        XCTAssertLessThanOrEqual(score.percent, 100)
    }
}
