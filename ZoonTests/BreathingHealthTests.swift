import XCTest

final class BreathingHealthTests: XCTestCase {

    // MARK: - elevation

    /// Apple's classification is the only source Zoon will call a night
    /// elevated from -- its cutoff is what Sleep Apnea Notifications is
    /// actually calibrated against.
    func testAppleClassificationDecidesElevated() {
        // A low raw value, but Apple says elevated.
        let night = Fixture.night(breathingDisturbances: 2.0, breathingDisturbancesClassification: .elevated)
        XCTAssertEqual(BreathingHealth.elevation(night), .elevated)
        XCTAssertTrue(BreathingHealth.isElevated(night))
    }

    func testAppleClassificationDecidesNotElevated() {
        // A high raw value, but Apple says not elevated.
        let night = Fixture.night(breathingDisturbances: 9.0, breathingDisturbancesClassification: .notElevated)
        XCTAssertEqual(BreathingHealth.elevation(night), .notElevated)
        XCTAssertFalse(BreathingHealth.isElevated(night))
    }

    /// The defect this replaced. `isElevated` used to substitute an in-app
    /// cutoff of `value >= 5.0` percent when Apple had not classified the
    /// night -- a number Zoon invented, that read as clinical, and that was
    /// printed on the clinician report as "nights classified elevated".
    ///
    /// A 9% night with no classification is now `.unclassified`, not
    /// elevated, because nothing has classified it.
    func testWithoutAppleClassificationNothingIsCalledElevated() {
        for value in [Double(0.5), 4.0, 6.0, 9.0, 40.0] {
            let night = Fixture.night(
                breathingDisturbances: value,
                breathingDisturbancesClassification: nil
            )
            XCTAssertEqual(BreathingHealth.elevation(night), .unclassified, "value \(value)")
            XCTAssertFalse(BreathingHealth.isElevated(night), "value \(value)")
        }
    }

    /// The other half of the old `Bool`: a night with no data at all returned
    /// `false`, which was indistinguishable from a night Apple examined and
    /// called not elevated. Now those are different answers.
    func testNoDataIsUnclassifiedRatherThanNotElevated() {
        let noData = Fixture.night(breathingDisturbances: nil, breathingDisturbancesClassification: nil)
        let examined = Fixture.night(breathingDisturbances: 3.0, breathingDisturbancesClassification: .notElevated)

        XCTAssertEqual(BreathingHealth.elevation(noData), .unclassified)
        XCTAssertEqual(BreathingHealth.elevation(examined), .notElevated)
        XCTAssertNotEqual(
            BreathingHealth.elevation(noData),
            BreathingHealth.elevation(examined),
            "no data and a clean classification are not the same answer"
        )
    }

    /// The correct denominator for any "N of M nights elevated" statement.
    func testClassifiedFiltersOutUnclassifiedNights() {
        let nights = [
            Fixture.night(daysAgo: 3, breathingDisturbances: 8.0, breathingDisturbancesClassification: nil),
            Fixture.night(daysAgo: 2, breathingDisturbances: 2.0, breathingDisturbancesClassification: .elevated),
            Fixture.night(daysAgo: 1, breathingDisturbances: 2.0, breathingDisturbancesClassification: .notElevated),
            Fixture.night(daysAgo: 0, breathingDisturbances: nil, breathingDisturbancesClassification: nil),
        ]
        XCTAssertEqual(BreathingHealth.classified(nights).count, 2)
    }

    // MARK: - compute / pattern

    func testRepeatedPatternUsesAppleClassificationNotJustRawValue() {
        // 14 nights, all with a raw value comfortably under the old 5% in-app
        // threshold, but Apple classifies 5 of them as elevated -- the
        // pattern should still fire, which a value-only threshold would have
        // missed entirely.
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
        XCTAssertEqual(windowNights, 14, "the window is the classified nights")
    }

    /// A window full of readings from a watch that does not classify them is
    /// `unclassified`, not `normal`. The old code called it normal, because
    /// its invented cutoff answered for every night -- so a user whose device
    /// never classifies anything was told their breathing was fine.
    func testUnclassifiedNightsDoNotReadAsNormal() {
        let nights = (0..<14).map {
            Fixture.night(daysAgo: 13 - $0, breathingDisturbances: 7.0, breathingDisturbancesClassification: nil)
        }
        let health = BreathingHealth.compute(nights: nights)

        guard case .unclassified(let windowNights) = health.pattern else {
            return XCTFail("expected unclassified, got \(health.pattern)")
        }
        XCTAssertEqual(windowNights, 14)
        XCTAssertNotEqual(health.pattern, .normal)
        // The trend is still real and still worth showing.
        XCTAssertEqual(health.disturbanceTrend.count, 14)
    }

    /// Mostly unclassified, with a couple classified, is still not enough to
    /// draw a conclusion from.
    func testTooFewClassifiedNightsIsUnclassified() {
        let nights = (0..<14).map { i in
            Fixture.night(
                daysAgo: 13 - i,
                breathingDisturbances: 3.0,
                breathingDisturbancesClassification: i < 2 ? .notElevated : nil
            )
        }
        if case .unclassified = BreathingHealth.compute(nights: nights).pattern {
            // expected
        } else {
            XCTFail("expected unclassified with only 2 classified nights")
        }
    }

    func testEnoughClassifiedCleanNightsReadsAsNormal() {
        let nights = (0..<14).map {
            Fixture.night(
                daysAgo: 13 - $0,
                breathingDisturbances: 3.0,
                breathingDisturbancesClassification: .notElevated
            )
        }
        XCTAssertEqual(BreathingHealth.compute(nights: nights).pattern, .normal)
    }

    func testTrendPointsCarryTheSameAnswerAsElevation() {
        let nights = [
            Fixture.night(daysAgo: 2, breathingDisturbances: 8.0, breathingDisturbancesClassification: .notElevated),
            Fixture.night(daysAgo: 1, breathingDisturbances: 1.0, breathingDisturbancesClassification: .elevated),
            Fixture.night(daysAgo: 0, breathingDisturbances: 6.0, breathingDisturbancesClassification: nil),
        ]
        let health = BreathingHealth.compute(nights: nights)
        XCTAssertEqual(health.disturbanceTrend.count, 3)
        for point in health.disturbanceTrend {
            guard let night = nights.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: point.date)
            }) else {
                return XCTFail("no matching fixture night for trend point \(point.date)")
            }
            XCTAssertEqual(point.elevation, BreathingHealth.elevation(night))
        }
    }

    func testInsufficientDataBelowMinimumNights() {
        let nights = (0..<4).map {
            Fixture.night(daysAgo: $0, breathingDisturbances: 8.0, breathingDisturbancesClassification: .elevated)
        }
        XCTAssertEqual(BreathingHealth.compute(nights: nights).pattern, .insufficientData)
    }

    // MARK: - Respiratory baseline

    /// The deviation-from-your-own-baseline read is what Zoon can honestly
    /// show without any classification at all.
    func testRespiratoryDeviationIsMeasuredAgainstTheUsersOwnBaseline() {
        var nights = (1..<10).map { Fixture.night(daysAgo: $0, avgRespiratoryRate: 14.0) }
        nights.append(Fixture.night(daysAgo: 0, avgRespiratoryRate: 16.8))
        let health = BreathingHealth.compute(nights: nights)

        XCTAssertEqual(health.baselineRespiratoryRate ?? 0, 14.0, accuracy: 0.001)
        XCTAssertEqual(health.respiratoryDeviationPercent ?? 0, 20.0, accuracy: 0.5)
    }
}
