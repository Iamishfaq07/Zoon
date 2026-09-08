import XCTest

final class DemographicBaselineTests: XCTestCase {

    func testDeepFractionDeclinesWithAge() {
        let young = DemographicBaseline(ageYears: 25, sex: .unspecified, bodyMassIndex: nil)
        let older = DemographicBaseline(ageYears: 55, sex: .unspecified, bodyMassIndex: nil)
        XCTAssertGreaterThan(young.expectedDeepFraction, older.expectedDeepFraction)
        // ~2 percentage points per decade after 30: 25 years is a 0.04 gap.
        XCTAssertEqual(young.expectedDeepFraction - older.expectedDeepFraction, 0.04, accuracy: 0.005)
    }

    func testATypicalOlderNightIsNotPenalised() {
        let prior = DemographicBaseline(ageYears: 55, sex: .male, bodyMassIndex: nil)
        let asleep = 450.0
        let typicalDeep = prior.expectedDeepFraction * asleep
        let contribution = prior.deepSleepScoreContribution(
            asleepMinutes: asleep, deepMinutes: typicalDeep
        )
        XCTAssertEqual(contribution ?? -1, 1.0, accuracy: 0.02)
    }

    func testSurplusDeepSleepDoesNotInflateTheContribution() {
        let prior = DemographicBaseline(ageYears: 25, sex: .female, bodyMassIndex: nil)
        let contribution = prior.deepSleepScoreContribution(asleepMinutes: 450, deepMinutes: 450)
        XCTAssertEqual(contribution ?? -1, 1.0, accuracy: 0.001)
    }

    func testMissingStagesYieldNilRatherThanZero() {
        let prior = DemographicBaseline(ageYears: 40, sex: .unspecified, bodyMassIndex: nil)
        XCTAssertNil(prior.deepSleepRatio(asleepMinutes: 0, deepMinutes: 0))
    }

    func testObeseBMINudgesThePriorDown() {
        let lean = DemographicBaseline(ageYears: 40, sex: .unspecified, bodyMassIndex: 22)
        let obese = DemographicBaseline(ageYears: 40, sex: .unspecified, bodyMassIndex: 32)
        XCTAssertGreaterThan(lean.expectedDeepFraction, obese.expectedDeepFraction)
    }

    func testAgeIsClampedRatherThanRejected() {
        let low = DemographicBaseline(ageYears: 5, sex: .unspecified, bodyMassIndex: nil)
        let adult = DemographicBaseline(ageYears: 18, sex: .unspecified, bodyMassIndex: nil)
        XCTAssertEqual(low.expectedDeepFraction, adult.expectedDeepFraction, accuracy: 0.0001)
    }

    func testSleepScoreDoesNotPenaliseATypicalOlderNight() {
        // 14% deep at 55 is typical for the prior; the un-normalised 18%
        // adult target would mark it down. The demographic path must not.
        let prior = DemographicBaseline(ageYears: 55, sex: .male, bodyMassIndex: nil)
        let asleep = 480.0
        let typicalDeep = prior.expectedDeepFraction * asleep
        let night = Fixture.night(
            timeAsleepMinutes: asleep,
            timeInBedMinutes: 500,
            deepMinutes: typicalDeep,
            remMinutes: prior.expectedRemFraction * asleep
        )
        let withPrior = SleepScore.compute(for: night, goalMinutes: 480, demographic: prior)
        let without = SleepScore.compute(for: night, goalMinutes: 480)
        let deepWith = withPrior.components.first { $0.label == "Deep" }?.normalized ?? 0
        let deepWithout = without.components.first { $0.label == "Deep" }?.normalized ?? 0
        XCTAssertEqual(deepWith, 1.0, accuracy: 0.02)
        XCTAssertLessThan(deepWithout, deepWith)
    }
}
