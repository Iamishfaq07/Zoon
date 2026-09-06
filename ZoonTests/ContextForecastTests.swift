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
        // One hour of bedtime difference, averaged over the five features
        // that were comparable. The magnitude moved when distance became a
        // mean; the equality above is the claim this test is really making.
        XCTAssertEqual(
            late.value,
            (1 / ContextForecast.bedtimeScale) / Double(ContextForecast.numericFeatureCount),
            accuracy: 1e-9
        )
    }

    /// A missing feature is never *imputed* -- filling a nil sleep debt with
    /// zero would assert the person was rested, which is a claim nobody made.
    /// But it is no longer free either: not knowing costs coverage, or a
    /// night Zoon knows nothing about becomes its own best match.
    func testAMissingFeatureIsNotImputedButStillCostsCoverage() {
        let known = context(debt: 240)
        let unknown = context(debt: nil)
        let distance = ContextForecast.distance(from: known, to: unknown)

        XCTAssertEqual(distance.comparedFeatures, 4)
        // Not 240 minutes of disagreement, and not nothing either: exactly
        // the coverage penalty for one absent feature out of five.
        XCTAssertEqual(
            distance.value,
            ContextForecast.missingCoveragePenalty / Double(ContextForecast.numericFeatureCount),
            accuracy: 1e-9
        )
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

    func testConfidenceNeedsEnoughNeighboursCloseOnesAndKnownOnes() {
        let near = ContextForecast.maximumDistance / 4
        let far = ContextForecast.maximumDistance * 0.9
        let full = 1.0

        XCTAssertEqual(ContextForecast.confidence(neighbours: 5, meanDistance: near, meanCoverage: full), .insufficient)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 13, meanDistance: near, meanCoverage: full), .moderate)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 13, meanDistance: far, meanCoverage: full), .low)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 18, meanDistance: near, meanCoverage: full), .high)
        XCTAssertEqual(ContextForecast.confidence(neighbours: 18, meanDistance: far, meanCoverage: full), .moderate)
    }

    func testManyDistantNeighboursNeverReachHighConfidence() {
        XCTAssertLessThan(
            ContextForecast.confidence(
                neighbours: 400,
                meanDistance: ContextForecast.maximumDistance,
                meanCoverage: 1.0
            ),
            .high
        )
    }

    /// The omission this release fixed one level down, at this level too:
    /// closeness is measured over whatever happened to be known, so plenty of
    /// close neighbours matched on two features out of five is not strong
    /// evidence however good the distance looks.
    func testManyCloseButSparselyMatchedNeighboursNeverReachHighConfidence() {
        let near = ContextForecast.maximumDistance / 4
        XCTAssertEqual(
            ContextForecast.confidence(neighbours: 30, meanDistance: near, meanCoverage: 0.4),
            .low
        )
        XCTAssertLessThan(
            ContextForecast.confidence(neighbours: 30, meanDistance: near, meanCoverage: 0.6),
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

    // MARK: - Less information must not look like a better match (V10 item 4)

    /// The bug, stated exactly as the spec states it. A candidate matching
    /// perfectly on two known features used to score 0 -- because distance was
    /// a *sum* and it had less to disagree about -- and therefore outranked a
    /// candidate matching closely on all five.
    func testTwoPerfectFeaturesDoNotBeatFiveGoodOnes() {
        let target = context()
        let sparse = ContextForecast.Context(
            isWeekend: false,
            sleepDebtMinutes: target.sleepDebtMinutes,
            bedtimeHour: target.bedtimeHour,
            lateCaffeineMg: nil,
            exerciseMinutesPreviousDay: nil,
            previousNightAsleepMinutes: nil
        )
        let rich = context(debt: 12, bedtime: 23.1, caffeine: 10, exercise: 36, previous: 449)

        let sparseDistance = ContextForecast.distance(from: target, to: sparse)
        let richDistance = ContextForecast.distance(from: target, to: rich)

        XCTAssertEqual(sparseDistance.comparedFeatures, 2)
        XCTAssertEqual(richDistance.comparedFeatures, 5)
        XCTAssertLessThan(
            richDistance.value, sparseDistance.value,
            "knowing less about a night made it look more comparable"
        )
    }

    /// Knowing nothing comparable is the worst case, not the best one.
    func testAFullyUnknownContextIsMaximallyDistant() {
        let unknown = ContextForecast.Context(
            isWeekend: false,
            sleepDebtMinutes: nil,
            bedtimeHour: nil,
            lateCaffeineMg: nil,
            exerciseMinutesPreviousDay: nil,
            previousNightAsleepMinutes: nil
        )
        let distance = ContextForecast.distance(from: context(), to: unknown)

        XCTAssertEqual(distance.comparedFeatures, 0)
        XCTAssertEqual(distance.value, ContextForecast.missingCoveragePenalty, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(distance.value, ContextForecast.maximumDistance,
                                    "a night with nothing to compare must not survive the ceiling")
    }

    /// Coverage degrades smoothly: each absent feature costs the same slice.
    func testEachMissingFeatureCostsAnEqualShareOfCoverage() {
        let step = ContextForecast.missingCoveragePenalty / Double(ContextForecast.numericFeatureCount)
        let one = ContextForecast.distance(from: context(), to: context(debt: nil))
        let two = ContextForecast.distance(from: context(), to: context(debt: nil, caffeine: nil))

        XCTAssertEqual(one.value, step, accuracy: 1e-9)
        XCTAssertEqual(two.value, 2 * step, accuracy: 1e-9)
    }

    /// An identical, fully-known night is still a perfect match -- the
    /// penalty must not leak into the case it is not about.
    func testAFullyKnownIdenticalNightIsStillZero() {
        XCTAssertEqual(ContextForecast.distance(from: context(), to: context()).value, 0, accuracy: 1e-9)
    }

    /// A partially-described night is usable, just penalised -- it is not
    /// excluded outright, since some real nights genuinely lack a field.
    func testAPartiallyDescribedNightIsStillEligible() {
        let partial = ContextForecast.distance(from: context(), to: context(caffeine: nil))
        XCTAssertLessThan(partial.value, ContextForecast.maximumDistance)
        XCTAssertGreaterThanOrEqual(partial.comparedFeatures, ContextForecast.minimumComparedFeatures)
    }

    /// End to end: the ranking prefers the well-described neighbours, so the
    /// interval is read off nights Zoon actually knows something about.
    func testTheForecastPrefersWellDescribedNeighbours() throws {
        // Twenty sparse nights that agree perfectly on what little they have,
        // and twenty fully-described ones that agree closely on everything.
        let sparse = (0..<20).map { index in
            ContextForecast.Sample(
                context: ContextForecast.Context(
                    isWeekend: false,
                    sleepDebtMinutes: 0,
                    bedtimeHour: 23,
                    lateCaffeineMg: nil,
                    exerciseMinutesPreviousDay: nil,
                    previousNightAsleepMinutes: nil
                ),
                outcome: 40 + Double(index % 3)
            )
        }
        let described = (0..<20).map { index in
            ContextForecast.Sample(
                context: self.context(debt: 4, bedtime: 23.05, caffeine: 2, exercise: 31, previous: 442),
                outcome: 80 + Double(index % 3)
            )
        }

        let prediction = try XCTUnwrap(
            ContextForecast.predict(for: context(), from: sparse + described)
        )
        XCTAssertTrue(prediction.basis.isConditioned)
        XCTAssertGreaterThan(prediction.lower, 70,
                             "the interval was read off the nights Zoon knows least about")
    }
}
