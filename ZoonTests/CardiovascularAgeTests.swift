import XCTest

final class CardiovascularAgeTests: XCTestCase {

    private func nights(count: Int, avgHRV: Double?, restingHeartRate: Double?) -> [SleepNightFeatures] {
        Fixture.consecutiveNights(count, template: { daysAgo in
            Fixture.night(
                daysAgo: daysAgo,
                avgHRV: avgHRV,
                restingHeartRate: restingHeartRate,
                // Isolate the metric under test: `restingHeartRate: nil`
                // must actually leave RHR unavailable, not silently fall
                // back to the fixture's non-nil `minHeartRate` default.
                minHeartRate: restingHeartRate == nil ? nil : 48
            )
        })
    }

    // MARK: - Guard clauses

    func testComputeReturnsNilWithoutChronologicalAge() {
        XCTAssertNil(CardiovascularAge.compute(nights: nights(count: 20, avgHRV: 55, restingHeartRate: 55), chronologicalAge: nil))
    }

    func testComputeReturnsNilBelowMinimumAge() {
        XCTAssertNil(CardiovascularAge.compute(nights: nights(count: 20, avgHRV: 55, restingHeartRate: 55), chronologicalAge: 17))
    }

    func testComputeReturnsNilAboveMaximumAge() {
        XCTAssertNil(CardiovascularAge.compute(nights: nights(count: 20, avgHRV: 55, restingHeartRate: 55), chronologicalAge: 100))
    }

    func testComputeReturnsNilWithFewerThanMinimumNights() {
        let short = nights(count: CardiovascularAge.minimumNights - 1, avgHRV: 55, restingHeartRate: 55)
        XCTAssertNil(CardiovascularAge.compute(nights: short, chronologicalAge: 35))
    }

    func testComputeReturnsNilWhenNeitherMetricClearsItsSampleFloor() {
        // 20 nights, but every night has both HRV and RHR nil.
        let sparse = Fixture.consecutiveNights(20, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, avgHRV: nil, restingHeartRate: nil, minHeartRate: nil)
        })
        XCTAssertNil(CardiovascularAge.compute(nights: sparse, chronologicalAge: 35))
    }

    func testComputeSucceedsWithEnoughNightsAndData() {
        let result = CardiovascularAge.compute(nights: nights(count: 20, avgHRV: 55, restingHeartRate: 55), chronologicalAge: 35)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.nightCount, 20)
    }

    // MARK: - Clamping

    func testEstimateNeverExceedsFifteenYearsFromChronologicalAge() {
        // An HRV far outside anything the population curve would produce at
        // this age should still clamp to the documented ±15-year bound.
        let extreme = nights(count: 20, avgHRV: 5, restingHeartRate: 55)
        let result = CardiovascularAge.compute(nights: extreme, chronologicalAge: 35)
        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(result!.deltaYears, 15.0001)
        XCTAssertGreaterThanOrEqual(result!.deltaYears, -15.0001)
    }

    // MARK: - Direction sanity

    func testHigherThanExpectedHRVReadsYounger() {
        // expectedHRV(35) ≈ 45ms; a well-above-expected reading should imply
        // a younger estimated age, not older.
        let result = CardiovascularAge.compute(nights: nights(count: 20, avgHRV: 70, restingHeartRate: nil), chronologicalAge: 35)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.estimatedAge, 35)
    }

    func testLowerThanExpectedHRVReadsOlder() {
        let result = CardiovascularAge.compute(nights: nights(count: 20, avgHRV: 25, restingHeartRate: nil), chronologicalAge: 35)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.estimatedAge, 35)
    }

    // MARK: - standing

    func testStandingBoundaries() {
        func standing(delta: Double) -> CardiovascularAge.Standing {
            CardiovascularAge(estimatedAge: 35 + delta, chronologicalAge: 35, nightCount: 20, averageHRV: nil, averageRestingHR: nil).standing
        }
        XCTAssertEqual(standing(delta: -5.1), .younger)
        XCTAssertEqual(standing(delta: -5), .aligned)
        XCTAssertEqual(standing(delta: 0), .aligned)
        XCTAssertEqual(standing(delta: 5), .aligned)
        XCTAssertEqual(standing(delta: 5.1), .older)
    }
}
