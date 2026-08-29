import XCTest

final class UncertaintyForecastTests: XCTestCase {

    /// `count` nights whose duration is drawn from a fixed spread around
    /// `centre`. Seeded, so an interval assertion can be exact rather than
    /// approximate.
    private func nights(
        _ count: Int, centre: Double = 450, spread: Double = 60, seed: UInt64 = 21
    ) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let asleep = centre + (spread == 0 ? 0 : generator.nextDouble(in: -spread...spread))
            return Fixture.night(
                daysAgo: count - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - The interval is the point

    func testForecastBracketsTheTypicalValue() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )

        XCTAssertLessThanOrEqual(forecast.lower, forecast.typical)
        XCTAssertLessThanOrEqual(forecast.typical, forecast.upper)
        XCTAssertGreaterThan(forecast.spread, 0)
    }

    /// The width of the interval is the informative part: an erratic sleeper
    /// must get a visibly wider forecast than a steady one, even when both
    /// centre on the same number.
    func testErraticNightsProduceAWiderIntervalThanSteadyOnes() throws {
        let steady = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21, spread: 10))
        )
        let erratic = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21, spread: 120))
        )

        XCTAssertGreaterThan(erratic.spread, steady.spread * 3,
                             "a far more variable sleeper should get a far wider interval")
    }

    /// The distinction this type exists to protect: a *prediction* interval
    /// tracks how variable the person is, and must not collapse toward zero
    /// just because more nights have been logged. A confidence interval
    /// would, and reporting one as a forecast would tell an erratic sleeper
    /// that tomorrow is nearly certain.
    func testIntervalDoesNotShrinkTowardZeroAsHistoryGrows() throws {
        let short = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(14, spread: 90))
        )
        let long = try XCTUnwrap(
            UncertaintyForecast.forecast(
                metric: .duration,
                nights: nights(60, spread: 90),
                minimumNights: 14
            )
        )

        XCTAssertGreaterThan(long.spread, short.spread * 0.5,
                             "more history must not masquerade as more certainty")
    }

    // MARK: - Refusing to guess

    func testTooLittleHistoryReturnsNil() {
        XCTAssertNil(UncertaintyForecast.forecast(metric: .duration, nights: nights(9)))
    }

    func testAMetricWithNoSamplesReturnsNil() {
        let history = (0..<21).map { index in
            Fixture.night(daysAgo: 21 - index, avgHRV: nil)
        }
        XCTAssertNil(UncertaintyForecast.forecast(metric: .hrv, nights: history))
    }

    /// Only the recent window feeds the forecast -- a schedule from two
    /// months ago should stop colouring tomorrow.
    func testOnlyTheRecentWindowIsUsed() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(90))
        )
        XCTAssertEqual(forecast.nightsUsed, UncertaintyForecast.window)
    }

    // MARK: - Confidence

    func testConfidenceRisesWithHistoryButNeverClaimsCertainty() throws {
        let sparse = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(15))
        )
        let full = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(40))
        )

        XCTAssertEqual(sparse.confidence, .low)
        XCTAssertEqual(full.confidence, .high, "the ceiling is high, not certain")
    }

    // MARK: - forecastAll

    func testForecastAllSortsMostPredictableFirst() {
        let forecasts = UncertaintyForecast.forecastAll(nights: nights(21))
        let relative = forecasts.map { $0.spread / max(abs($0.typical), 1) }
        XCTAssertEqual(relative, relative.sorted())
    }

    func testForecastAllSkipsMetricsWithoutEnoughData() {
        XCTAssertTrue(UncertaintyForecast.forecastAll(nights: nights(5)).isEmpty)
    }

    // MARK: - Copy

    func testSentenceLeadsWithTheRangeNotTheMidpoint() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )

        XCTAssertTrue(forecast.sentence.contains("between"), forecast.sentence)
        // The range must appear before the typical value in the sentence.
        let betweenIndex = try XCTUnwrap(forecast.sentence.range(of: "between")).lowerBound
        let typicallyIndex = try XCTUnwrap(forecast.sentence.range(of: "typically")).lowerBound
        XCTAssertLessThan(betweenIndex, typicallyIndex)
    }

    /// A forecast built only from past nights knows nothing about the
    /// person's actual plans, and must say so.
    func testCaveatDisclaimsKnowledgeOfPlans() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )

        XCTAssertTrue(forecast.caveat.contains("doesn't know your plans"), forecast.caveat)
        XCTAssertTrue(forecast.caveat.contains("\(forecast.nightsUsed) nights"), forecast.caveat)
    }

    func testNoCopyPromisesACertainOutcome() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )
        for text in [forecast.sentence, forecast.caveat] {
            let lower = text.lowercased()
            XCTAssertFalse(lower.contains("will be"), text)
            XCTAssertFalse(lower.contains("guarantee"), text)
        }
    }

    /// V8 Task 9: until a context-conditioned model exists and has been
    /// backtested, this type reports where recent nights *landed*. It must not
    /// phrase that as a claim about tomorrow — the numbers behind it are the
    /// median and 10th/90th percentiles of recent values, with no calibration
    /// against what actually happened next.
    func testCopyDoesNotPresentTheRangeAsAPredictionAboutTomorrow() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )
        for text in [forecast.sentence, forecast.caveat] {
            let lower = text.lowercased()
            XCTAssertFalse(lower.contains("tomorrow will"), text)
            XCTAssertFalse(lower.contains("most likely land"), text)
            XCTAssertFalse(lower.contains("expect"), text)
        }
    }

    /// The range itself still has to be legible, or the honesty fix would
    /// have removed the information along with the overclaim.
    func testSentenceStillReportsTheRangeAndTypicalValue() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )

        XCTAssertTrue(forecast.sentence.contains("between"), forecast.sentence)
        XCTAssertTrue(forecast.sentence.contains("typically"), forecast.sentence)
    }

    // MARK: - Language, on every surface

    /// #226 corrected `sentence` and `caveat` but not `rangeLabel` -- the
    /// compact string the widget and the watch actually render. The widget
    /// then framed it under a header reading "Tomorrow", restating the
    /// prediction in the one place a caveat cannot fit.
    ///
    /// This covers the third string. The widget's own header is a view
    /// literal no unit test can reach; it carries a comment instead, which is
    /// the weaker guard and worth knowing about.
    func testRangeLabelDoesNotPredictEither() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )
        let lower = forecast.rangeLabel.lowercased()
        for banned in ["tomorrow", "will be", "most likely", "expect", "predict"] {
            XCTAssertFalse(lower.contains(banned), "\(banned) in: \(forecast.rangeLabel)")
        }
    }

    /// And still carries both ends, so the honesty fix cannot quietly become
    /// an empty label.
    func testRangeLabelStillCarriesBothEnds() throws {
        let forecast = try XCTUnwrap(
            UncertaintyForecast.forecast(metric: .duration, nights: nights(21))
        )
        XCTAssertTrue(forecast.rangeLabel.contains(" to "), forecast.rangeLabel)
        XCTAssertTrue(
            forecast.rangeLabel.contains(forecast.metric.formattedMagnitude(forecast.lower)),
            forecast.rangeLabel
        )
        XCTAssertTrue(
            forecast.rangeLabel.contains(forecast.metric.formattedMagnitude(forecast.upper)),
            forecast.rangeLabel
        )
    }
}
