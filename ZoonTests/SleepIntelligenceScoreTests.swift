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

    func testCanonicalWeightsPrioritizeDurationAndContinuity() {
        let weights = Dictionary(uniqueKeysWithValues: SleepIntelligenceScore.nominalWeights)
        XCTAssertEqual(weights["Duration"], 0.40)
        XCTAssertEqual(weights["Continuity"], 0.30)
        XCTAssertEqual(weights.values.reduce(0, +), 1.0, accuracy: 0.0001)
    }

    /// Tonight's midpoint is folded at 18:00 (so a 17:00 bedtime reads as
    /// +17) while `BodyClock.midpoint` folds at 12:00 (so a 20:30 habit
    /// reads as -3.5). Subtracting the two directly called an on-time
    /// evening-shift sleeper a full day off their usual timing.
    func testTimingDriftIsMeasuredOnTheClockCircle() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let bedtime = try XCTUnwrap(calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today))
        let wakeTime = bedtime.addingTimeInterval(7 * 3600)
        let night = SleepNightFeatures(
            date: calendar.startOfDay(for: wakeTime),
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: 420,
            timeAsleepMinutes: 420,
            sleepEfficiencyPercent: 100,
            coreMinutes: 420,
            deepMinutes: 0,
            remMinutes: 0,
            unspecifiedAsleepMinutes: 0,
            awakeMinutes: 0,
            wakeCount: 0,
            sleepLatencyMinutes: nil,
            avgHeartRate: nil,
            minHeartRate: nil,
            avgHRV: nil,
            avgRespiratoryRate: nil,
            avgSpO2: nil,
            wristTempDeltaC: nil,
            hrv7DayAvg: nil,
            sleepDebtMinutes: nil,
            lastWorkoutHoursBeforeBed: nil,
            exerciseMinutesPreviousDay: nil,
            sourceName: "Fixture"
        )

        // Midpoint 20:30 tonight, habitual midpoint 20:30 (-3.5 signed).
        let score = SleepIntelligenceScore.compute(.init(
            night: night, history: [], sleepNeedMinutes: 420,
            regularityIndex: nil, habitualMidpointHours: -3.5
        ))

        let timing = try XCTUnwrap(score.components.first { $0.label == "Timing" })
        XCTAssertGreaterThanOrEqual(timing.normalized, 0.99)
    }

    /// Duration alone (0.40 of the model) is never enough to state a
    /// confidence -- the old `>= 40` gate could not fail because Duration
    /// is always present. Duration plus Continuity (0.70) is the floor.
    func testDurationAloneIsInsufficientConfidence() {
        let durationOnly = Fixture.night(timeAsleepMinutes: 0, timeInBedMinutes: 480)
        let insufficient = SleepIntelligenceScore.compute(.init(
            night: durationOnly, history: [], sleepNeedMinutes: 450,
            regularityIndex: nil, habitualMidpointHours: nil
        ))
        XCTAssertEqual(insufficient.dataCompletenessPercent, 40)
        XCTAssertEqual(insufficient.confidence, .insufficient)

        let withContinuity = SleepIntelligenceScore.compute(.init(
            night: Fixture.night(daysAgo: 0), history: [], sleepNeedMinutes: 450,
            regularityIndex: nil, habitualMidpointHours: nil
        ))
        XCTAssertEqual(withContinuity.dataCompletenessPercent, 70)
        XCTAssertEqual(withContinuity.confidence, .low)
    }
}
