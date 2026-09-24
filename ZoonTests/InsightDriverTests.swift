import XCTest

/// A generated insight may name a cause only by choosing one the rules
/// proved from tonight's data (audit §7.1).
final class InsightDriverTests: XCTestCase {

    private let lateWorkout = InsightDriver(id: "late-workout", observed: "Your workout ended about 1h before bed.")
    private let shortSleep = InsightDriver(id: "short-sleep", observed: "You slept 5h 30m against a 7h 30m goal.")

    func testAnOfferedIdResolvesToTheRulesOwnSentence() {
        XCTAssertEqual(
            InsightDriverSelection.resolve("late-workout", eligible: [lateWorkout, shortSleep]),
            .driver(lateWorkout)
        )
        XCTAssertEqual(
            InsightDriverSelection.resolve("  Late-Workout \n", eligible: [lateWorkout]),
            .driver(lateWorkout),
            "case and whitespace are not evidence"
        )
    }

    func testNoneMeansNoCause() {
        for token in ["", "none", "None", "null", "n/a", "  "] {
            XCTAssertEqual(InsightDriverSelection.resolve(token, eligible: [lateWorkout]), .none, token)
        }
    }

    /// The audit's example: caffeine was never in the evidence.
    func testAnIdThatWasNotOfferedIsRejected() {
        XCTAssertEqual(
            InsightDriverSelection.resolve("caffeine", eligible: [lateWorkout, shortSleep]),
            .rejected("caffeine")
        )
        XCTAssertEqual(
            InsightDriverSelection.resolve("late-workout", eligible: [shortSleep]),
            .rejected("late-workout"),
            "a real rule id is still invented evidence on a night it did not fire"
        )
        XCTAssertEqual(
            InsightDriverSelection.resolve("Caffeine late in the day disrupted your sleep", eligible: [lateWorkout]),
            .rejected("caffeine late in the day disrupted your sleep"),
            "free text is not an id"
        )
    }

    func testThePromptOffersExactlyTheEligibleIds() {
        let block = InsightDriverSelection.promptBlock([lateWorkout, shortSleep])
        XCTAssertTrue(block.contains("- late-workout: "), block)
        XCTAssertTrue(block.contains("- short-sleep: "), block)
        XCTAssertTrue(InsightDriverSelection.promptBlock([]).contains("none"))
    }

    // MARK: - Eligibility comes from the rules

    /// Two weeks of history with a usual 100 minutes of deep sleep.
    private func baseline() -> RollingBaseline {
        RollingBaseline(
            hrv7DayAvg: 55, sleepDebtMinutes: 0, deep7DayAvg: 100,
            duration7DayAvg: 470, efficiency7DayAvg: 92, minHeartRate7DayAvg: 48,
            restingHeartRate7DayAvg: 54, wristTempBaselineC: 34.0,
            bedtimeConsistencyMinutes: 25, sampleCount: 14
        )
    }

    func testALateWorkoutNightMakesLateWorkoutEligible() {
        // The rule needs both: a workout within two hours of bed *and* deep
        // sleep well under the usual.
        let night = Fixture.night(daysAgo: 0, lastWorkoutHoursBeforeBed: 0.5, deepMinutes: 60)
        let ids = RuleBasedInsightEngine()
            .eligibleDrivers(for: night, baseline: baseline(), goalMinutes: 480)
            .map(\.id)
        XCTAssertTrue(ids.contains("late-workout"), "\(ids)")
        XCTAssertFalse(ids.contains("caffeine"))
    }

    func testAnOrdinaryNightOffersNothingToCite() {
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 480, timeInBedMinutes: 500, wakeCount: 1, deepMinutes: 95)
        let drivers = RuleBasedInsightEngine().eligibleDrivers(
            for: night, baseline: baseline(), goalMinutes: 480
        )
        XCTAssertFalse(drivers.contains { $0.id == "late-workout" || $0.id == "short-sleep" }, "\(drivers.map(\.id))")
    }

    /// The first eligible driver is the one the rule engine itself would
    /// have shown -- the two paths agree on what is strongest.
    func testEligibleDriversAreOrderedLikeTheRuleEngine() throws {
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 330, lastWorkoutHoursBeforeBed: 0.5, deepMinutes: 40)
        let engine = RuleBasedInsightEngine()
        let first = try XCTUnwrap(engine.eligibleDrivers(for: night, baseline: baseline(), goalMinutes: 480).first)
        let insight = engine.generate(for: night, baseline: baseline(), goalMinutes: 480, band: nil)
        XCTAssertEqual(first.observed, insight.likelyCause)
    }
}
