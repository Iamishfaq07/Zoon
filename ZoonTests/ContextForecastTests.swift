import XCTest

final class ContextForecastTests: XCTestCase {

    // MARK: - Building contexts

    private func context(
        weekend: Bool = false,
        debt: Double? = 0,
        bedtime: Double? = 23,
        caffeine: Double? = 0,
        exercise: Double? = 30,
        previous: Double? = 440
    ) -> ContextForecast.Context {
        ContextForecast.Context(
            isWeekend: weekend,
            sleepDebtMinutes: debt,
            bedtimeHour: bedtime,
            lateCaffeineMg: caffeine,
            exerciseMinutesPreviousDay: exercise,
            previousNightAsleepMinutes: previous
        )
    }

    // MARK: - Distance

    func testAContextIsZeroDistanceFromItself() {
        let distance = ContextForecast.distance(from: context(), to: context())
        XCTAssertEqual(distance.value, 0, accuracy: 1e-9)
        XCTAssertEqual(distance.comparedFeatures, 5)
    }

    func testAWeekendMismatchCostsThePenalty() {
        let distance = ContextForecast.distance(
            from: context(weekend: false), to: context(weekend: true)
        )
        XCTAssertEqual(distance.value, ContextForecast.weekendMismatchPenalty, accuracy: 1e-9)
    }

    /// Midnight is the whole point: 23:30 and 00:30 are an hour apart, and a
    /// straight subtraction calls them twenty-three.
    func testBedtimeIsComparedAroundTheClockNotAlongIt() {
        let late = ContextForecast.distance(
            from: context(bedtime: 23.5), to: context(bedtime: 0.5)
        )
        let same = ContextForecast.distance(
            from: context(bedtime: 23.5), to: context(bedtime: 22.5)
        )
        XCTAssertEqual(late.value, same.value, accuracy: 1e-9)
        XCTAssertEqual(late.value, 1 / ContextForecast.bedtimeScale, accuracy: 1e-9)
    }

    /// A missing feature is skipped, never imputed. Filling a nil sleep debt
    /// with zero would assert the person was rested, which is a claim.
    func testAMissingFeatureIsSkippedRatherThanTreatedAsZero() {
        let known = context(debt: 240)
        let unknown = context(debt: nil)
        let distance = ContextForecast.distance(from: known, to: unknown)

        XCTAssertEqual(distance.comparedFeatures, 4)
        XCTAssertEqual(distance.value, 0, accuracy: 1e-9,
                       "the unknown debt must not contribute distance in either direction")
    }

    func testDistanceScalesAreComparableAcrossFeatures() {
        // Two hours of bedtime shift and two hours of sleep debt should cost
        // about the same, or whichever feature is measured in bigger numbers
        // silently decides every match.
        let bedtime = ContextForecast.distance(from: context(), to: context(bedtime: 21))
        let debt = ContextForecast.distance(from: context(), to: context(debt: 120))
        XCTAssertEqual(bedtime.value, debt.value, accuracy: 1e-9)
    }

    // MARK: - Predicting

    /// A person whose weekends score far better than their weekdays. The
    /// unconditioned range spans both populations and says nothing; a
    /// conditioned one should land on the right half.
    private func splitLifeSamples() -> [ContextForecast.Sample] {
        (0..<60).map { index in
            let weekend = index % 7 >= 5
            let wobble = Double((index * 37) % 11) / 10 - 0.5
            return ContextForecast.Sample(
                context: context(
                    weekend: weekend,
                    debt: weekend ? 20 : 180,
                    bedtime: 23,
                    caffeine: weekend ? 5 : 100,
                    exercise: 25,
                    previous: 440
                ),
                outcome: (weekend ? 88 : 68) + wobble
            )
        }
    }

    func testAConditionedIntervalIsNarrowerThanTheUnconditionedOne() throws {
        let samples = splitLifeSamples()
        let weekday = try XCTUnwrap(ContextForecast.predict(
            for: context(weekend: false, debt: 180, caffeine: 100), from: samples
        ))

        // The unconditioned interval, computed directly from every outcome --
        // exactly what `UncertaintyForecast` would report for this person.
        // Comparing against another `predict` call would compare two matched
        // sets, not matched against unmatched.
        let outcomes = samples.map(\.outcome)
        let wide = try XCTUnwrap(Statistics.percentile(outcomes, ContextForecast.upperPercentile))
            - (try XCTUnwrap(Statistics.percentile(outcomes, ContextForecast.lowerPercentile)))

        XCTAssertTrue(weekday.basis.isConditioned)
        XCTAssertLessThan(weekday.spread, wide,
                          "conditioning on tomorrow taught the interval nothing")
    }

    func testTheIntervalLandsOnTheMatchingPopulation() throws {
        let samples = splitLifeSamples()

        let weekday = try XCTUnwrap(ContextForecast.predict(
            for: context(weekend: false, debt: 180, caffeine: 100), from: samples
        ))
        let weekend = try XCTUnwrap(ContextForecast.predict(
            for: context(weekend: true, debt: 20, caffeine: 5), from: samples
        ))

        XCTAssertLessThan(weekday.upper, 75, "weekday forecast leaked into weekend nights")
        XCTAssertGreaterThan(weekend.lower, 80, "weekend forecast leaked into weekday nights")
        XCTAssertLessThan(weekday.upper, weekend.lower)
    }

    /// The failure that matters. A night unlike anything in the history must
    /// not produce a confident-looking matched interval built from whichever
    /// eighteen nights happened to be least unlike it.
    func testANightUnlikeAnythingFallsBackRatherThanInventingAMatch() throws {
        let prediction = try XCTUnwrap(ContextForecast.predict(
            for: context(debt: 900, bedtime: 4, caffeine: 600, exercise: 300, previous: 120),
            from: splitLifeSamples()
        ))

        XCTAssertFalse(prediction.basis.isConditioned)
        if case .recentRange(let count) = prediction.basis {
            XCTAssertEqual(count, 60)
        } else {
            XCTFail("expected a recent-range basis, got \(prediction.basis)")
        }
        XCTAssertEqual(prediction.confidence, .low)
    }

    func testAFallbackSaysSoInItsOwnSentence() throws {
        let prediction = try XCTUnwrap(ContextForecast.predict(
            for: context(debt: 900, bedtime: 4, caffeine: 600, exercise: 300, previous: 120),
            from: splitLifeSamples()
        ))
        XCTAssertTrue(prediction.sentence().contains("Not enough of them resembled tomorrow"))
    }

    func testNoForecastAtAllBelowTheMinimumHistory() {
        let thin = Array(splitLifeSamples().prefix(UncertaintyForecast.minimumNights - 1))
        XCTAssertNil(ContextForecast.predict(for: context(), from: thin))
    }

    // MARK: - Never a point estimate

    /// The spec is explicit: "Always return interval … Never: Tomorrow will
    /// be 83." Nothing this type renders may be a single number.
    func testTheRangeLabelIsAlwaysAnInterval() throws {
        for target in [context(weekend: false, debt: 180, caffeine: 100),
                       context(weekend: true, debt: 20, caffeine: 5),
                       context(debt: 900, bedtime: 4, caffeine: 600)] {
            let prediction = try XCTUnwrap(
                ContextForecast.predict(for: target, from: splitLifeSamples())
            )
            XCTAssertTrue(prediction.rangeLabel().contains("–"),
                          "not an interval: \(prediction.rangeLabel())")
            XCTAssertLessThanOrEqual(prediction.lower, prediction.upper)
        }
    }

    func testTheSentenceNeverPromisesASingleOutcome() throws {
        let prediction = try XCTUnwrap(ContextForecast.predict(
            for: context(weekend: false, debt: 180, caffeine: 100), from: splitLifeSamples()
        ))
        for phrase in ["will be", "you'll get", "expect exactly", "tomorrow will"] {
            XCTAssertFalse(prediction.sentence().lowercased().contains(phrase),
                           "promised an outcome: \(prediction.sentence())")
        }
    }

    // MARK: - Confidence

    func testConfidenceNeedsBothEnoughNeighboursAndCloseOnes() {
        let near = ContextForecast.maximumDistance / 4
        let far = ContextForecast.maximumDistance * 0.9

        XCTAssertEqual(ContextForecast.confidence(neighbours: 5, meanDistance: near), .insufficient)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 13, meanDistance: near), .moderate)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 13, meanDistance: far), .low)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 18, meanDistance: near), .high)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 18, meanDistance: far), .moderate)
    }

    func testManyDistantNeighboursNeverReachHighConfidence() {
        XCTAssertLessThan(
            ContextForecast.confidence(neighbours: 400, meanDistance: ContextForecast.maximumDistance),
            .high
        )
    }

    // MARK: - Reading context off real nights

    func testDescribingANightReadsItsBedtimeHour() throws {
        // The fixture wakes at 07:00, so eight hours in bed puts bedtime at
        // 23:00 and seven hours puts it at midnight.
        let eight = ContextForecast.Context.describing(Fixture.night(timeInBedMinutes: 480))
        XCTAssertEqual(try XCTUnwrap(eight.bedtimeHour), 23, accuracy: 0.01)

        let seven = ContextForecast.Context.describing(Fixture.night(timeInBedMinutes: 420))
        XCTAssertEqual(try XCTUnwrap(seven.bedtimeHour), 0, accuracy: 0.01)
    }

    func testDescribingANightCarriesItsDebt() {
        let night = ContextForecast.Context.describing(Fixture.night(sleepDebtMinutes: 210))
        XCTAssertEqual(night.sleepDebtMinutes, 210)
    }

    func testTheFirstNightHasNoPreviousNight() {
        let samples = ContextForecast.samples(from: Fixture.consecutiveNights(5)) { $0.timeAsleepMinutes }
        XCTAssertNil(samples.first?.context.previousNightAsleepMinutes)
        XCTAssertNotNil(samples.last?.context.previousNightAsleepMinutes)
    }

    func testSamplesLinkEachNightToTheOneBeforeIt() {
        let nights = Fixture.consecutiveNights(4) { index in
            Fixture.night(daysAgo: index, timeAsleepMinutes: 400 + Double(index) * 10)
        }
        let samples = ContextForecast.samples(from: nights) { $0.timeAsleepMinutes }
        let ordered = nights.sorted { $0.date < $1.date }

        XCTAssertEqual(samples.count, 4)
        for index in 1..<samples.count {
            XCTAssertEqual(
                samples[index].context.previousNightAsleepMinutes,
                ordered[index - 1].timeAsleepMinutes,
                "sample \(index) is not linked to the night before it"
            )
        }
    }

    /// A night with no outcome teaches nothing about tomorrow's and must not
    /// silently become a zero.
    func testNightsWithNoOutcomeAreDroppedNotZeroed() {
        let samples = ContextForecast.samples(from: Fixture.consecutiveNights(6)) { night in
            night.timeAsleepMinutes > 0 ? nil : night.timeAsleepMinutes
        }
        XCTAssertTrue(samples.isEmpty)
    }
}
