import XCTest

final class BreathingHealthTests: XCTestCase {

    // MARK: - isElevated

    /// The actual fix: Apple's own classification takes priority over the
    /// in-app percent threshold, even when the raw value would say otherwise
    /// -- Apple's cutoff is what its Sleep Apnea Notifications feature is
    /// actually calibrated against, not a number this app invented.
    func testAppleClassificationOverridesInAppThresholdWhenElevated() {
        // Below the in-app 5% threshold, but Apple says elevated.
        let night = Fixture.night(breathingDisturbances: 2.0, breathingDisturbancesClassification: .elevated)
        XCTAssertTrue(BreathingHealth.isElevated(night))
    }

    func testAppleClassificationOverridesInAppThresholdWhenNotElevated() {
        // Above the in-app 5% threshold, but Apple says not elevated.
        let night = Fixture.night(breathingDisturbances: 9.0, breathingDisturbancesClassification: .notElevated)
        XCTAssertFalse(BreathingHealth.isElevated(night))
    }

    func testFallsBackToPercentThresholdWithoutAppleClassification() {
        let elevated = Fixture.night(breathingDisturbances: 6.0, breathingDisturbancesClassification: nil)
        let notElevated = Fixture.night(breathingDisturbances: 4.0, breathingDisturbancesClassification: nil)
        XCTAssertTrue(BreathingHealth.isElevated(elevated))
        XCTAssertFalse(BreathingHealth.isElevated(notElevated))
    }

    func testNoMeasuredValueAndNoClassificationIsNotElevated() {
        let night = Fixture.night(breathingDisturbances: nil, breathingDisturbancesClassification: nil)
        XCTAssertFalse(BreathingHealth.isElevated(night))
    }

    // MARK: - compute / pattern

    func testRepeatedPatternUsesAppleClassificationNotJustRawValue() {
        // 14 nights, all with a raw value comfortably under the old 5%
        // in-app threshold, but Apple classifies 5 of them as elevated --
        // the pattern should still fire, which the old value-only
        // threshold would have missed entirely.
        let nights = (0..<14).map { i -> SleepNightFeatures in
            Fixture.night(
                daysAgo: 13 - i,
                breathingDisturbances: 2.0,
                breathingDisturbancesClassification: i < 5 ? .elevated : .notElevated
            )
        }
        let health = BreathingHealth.compute(nights: nights)
        guard case .repeatedPattern(let nightsElevated, let windowNights) = health.pattern else {
            return XCTFail("expected a repeated pattern, got \(health.pattern)")
        }
        XCTAssertEqual(nightsElevated, 5)
        XCTAssertEqual(windowNights, 14)
    }

    func testTrendPointsCarryTheSameElevatedAnswerAsIsElevated() {
        let nights = [
            Fixture.night(daysAgo: 1, breathingDisturbances: 8.0, breathingDisturbancesClassification: .notElevated),
            Fixture.night(daysAgo: 0, breathingDisturbances: 1.0, breathingDisturbancesClassification: .elevated)
        ]
        let health = BreathingHealth.compute(nights: nights)
        XCTAssertEqual(health.disturbanceTrend.count, 2)
        for point in health.disturbanceTrend {
            guard let night = nights.first(where: { Calendar.current.isDate($0.date, inSameDayAs: point.date) }) else {
                return XCTFail("no matching fixture night for trend point \(point.date)")
            }
            XCTAssertEqual(point.isElevated, BreathingHealth.isElevated(night))
        }
    }

    func testInsufficientDataBelowMinimumNights() {
        let nights = (0..<4).map { Fixture.night(daysAgo: $0, breathingDisturbances: 8.0) }
        let health = BreathingHealth.compute(nights: nights)
        XCTAssertEqual(health.pattern, .insufficientData)
    }
}
