import XCTest

/// Asking a chart a question.
///
/// The point of these tests is that the question is *deterministic* and the
/// context is *typed*. A model that invented its own question from a gesture
/// would make the answer unauditable, and one shown a picture of a line
/// would have to guess everything that is computed here.
final class ChartQuestionTests: XCTestCase {

    private let night = Date(timeIntervalSince1970: 1_700_000_000)

    private func question(
        metric: TrendEngine.Metric = .hrv,
        value: Double,
        baseline: Double?,
        baselineNights: Int = 14
    ) -> ChartQuestion {
        var q = ChartQuestion(subject: .trend(metric), selected: .init(date: night, value: value))
        q.baseline = baseline
        q.baselineNightCount = baseline == nil ? 0 : baselineNights
        return q
    }

    // MARK: - Deviation

    /// The same rule `TrendEngine` uses to decide a shift is worth
    /// reporting. A separate threshold here would let the app call a night
    /// "low" on one screen and unremarkable on another.
    func testAClearDropIsBelowBaseline() {
        XCTAssertEqual(question(value: 50, baseline: 60).deviation, .below)
    }

    func testAClearRiseIsAboveBaseline() {
        XCTAssertEqual(question(value: 70, baseline: 60).deviation, .above)
    }

    func testASmallWobbleIsTypical() {
        // 5% on HRV, under the metric's own 10% threshold.
        XCTAssertEqual(question(value: 57, baseline: 60).deviation, .typical)
    }

    func testNoBaselineMeansUnknownRatherThanTypical() {
        XCTAssertEqual(question(value: 50, baseline: nil).deviation, .unknown)
    }

    /// A baseline resting on nothing is not a baseline.
    func testAZeroNightBaselineIsUnknown() {
        var q = question(value: 50, baseline: 60)
        q.baselineNightCount = 0
        XCTAssertEqual(q.deviation, .unknown)
    }

    // MARK: - The question

    func testTheQuestionNamesTheDirectionAndTheMetric() {
        let asked = question(value: 50, baseline: 60).question
        XCTAssertTrue(asked.contains("lower"), asked)
        XCTAssertTrue(asked.contains(TrendEngine.Metric.hrv.label), asked)
        XCTAssertTrue(asked.hasSuffix("?"), asked)
    }

    func testARiseAsksWhyItWasHigher() {
        XCTAssertTrue(question(value: 70, baseline: 60).question.contains("higher"))
    }

    /// Which direction is *good* is already in `higherIsBetter` and belongs
    /// in the answer. Asking "why was my sleep worse" pre-loads the reply
    /// with a judgement the data has not made.
    func testTheQuestionNeverJudges() {
        for value in [50.0, 70.0, 57.0] {
            let asked = question(value: value, baseline: 60).question
            XCTAssertFalse(asked.lowercased().contains("worse"), asked)
            XCTAssertFalse(asked.lowercased().contains("better"), asked)
            XCTAssertFalse(asked.lowercased().contains("bad"), asked)
        }
    }

    func testAnUnremarkableNightAsksAnOpenQuestion() {
        let asked = question(value: 57, baseline: 60).question
        XCTAssertTrue(asked.contains("What was going on"), asked)
    }

    /// Tapping the same point twice must ask the same thing.
    func testTheQuestionIsDeterministic() {
        let first = question(value: 50, baseline: 60).question
        let second = question(value: 50, baseline: 60).question
        XCTAssertEqual(first, second)
    }

    // MARK: - The context

    func testContextCarriesTheBaselineAndTheGap() {
        let context = question(value: 50, baseline: 60).context
        XCTAssertTrue(context.contains("Their baseline:"), context)
        XCTAssertTrue(context.contains("14 nights"), context)
        XCTAssertTrue(context.contains("below that baseline"), context)
    }

    /// Silence about the baseline reads as "unremarkable". A missing one is
    /// stated so the model cannot treat the comparison as having been made.
    func testAMissingBaselineIsStatedNotOmitted() {
        let context = question(value: 50, baseline: nil).context
        XCTAssertTrue(context.contains("No established baseline"), context)
        XCTAssertFalse(context.contains("Their baseline:"), context)
    }

    /// A model shown "Logged that day:" with nothing after it will invent
    /// something to have been logged.
    func testEmptySideContextProducesNoLine() {
        let context = question(value: 50, baseline: 60).context
        XCTAssertFalse(context.contains("Logged that day"), context)
        XCTAssertFalse(context.contains("Activity that day"), context)
        XCTAssertFalse(context.contains("Body signals"), context)
        XCTAssertFalse(context.contains("Nearby nights"), context)
    }

    func testSideContextIsIncludedWhenPresent() {
        var q = question(value: 50, baseline: 60)
        q.journal = ["late caffeine"]
        q.workouts = ["48 min run"]
        q.bodySignals = ["wrist temperature 0.4°C above baseline"]
        q.sleep = "6h 12m asleep"
        q.nearby = [
            .init(date: night.addingTimeInterval(-86_400), value: 58),
            .init(date: night.addingTimeInterval(86_400), value: 61)
        ]
        let context = q.context
        XCTAssertTrue(context.contains("late caffeine"), context)
        XCTAssertTrue(context.contains("48 min run"), context)
        XCTAssertTrue(context.contains("wrist temperature"), context)
        XCTAssertTrue(context.contains("6h 12m asleep"), context)
        XCTAssertTrue(context.contains("Nearby nights:"), context)
    }

    /// Every line is a fact that was passed in. The context must never
    /// contain a number nobody supplied.
    func testContextContainsNoUnsuppliedNumbers() {
        let context = question(value: 50, baseline: 60).context
        let digits = context.split(whereSeparator: { !$0.isNumber })
        XCTAssertTrue(digits.contains("50"), context)
        XCTAssertTrue(digits.contains("60"), context)
        XCTAssertTrue(digits.contains("14"), context)
    }

    // MARK: - Formatting

    /// `TrendEngine.formattedMagnitude` cannot serve bedtime: its values are
    /// signed minutes from midnight, so an 11pm bedtime formatted as a
    /// duration prints "-1h 0m".
    func testAnEveningBedtimeReadsAsAClockTime() {
        let q = ChartQuestion(subject: .trend(.bedtime), selected: .init(date: night, value: -30))
        XCTAssertEqual(q.formatted(-30), "23:30")
    }

    func testAnAfterMidnightBedtimeReadsAsAClockTime() {
        let q = ChartQuestion(subject: .trend(.bedtime), selected: .init(date: night, value: 90))
        XCTAssertEqual(q.formatted(90), "01:30")
    }

    /// A bedtime *gap* is a duration, not a clock time.
    func testABedtimeDifferenceIsADuration() {
        let q = ChartQuestion(subject: .trend(.bedtime), selected: .init(date: night, value: -30))
        XCTAssertEqual(q.formattedMagnitude(40), SleepNightFeatures.formatMinutes(40))
    }

    // MARK: - Building one from a charted window

    /// A value compared against a baseline it is itself part of is compared
    /// against a slightly dragged version of itself.
    func testTheBaselineExcludesTheSelectedNight() throws {
        // Four nights at 50ms and one outlier at 90ms. Including the outlier
        // would pull its own baseline up to 55.
        var nights = (1...4).map { Fixture.night(daysAgo: $0, avgHRV: 50) }
        let outlier = Fixture.night(daysAgo: 0, avgHRV: 90)
        nights.append(outlier)

        let question = try XCTUnwrap(
            ChartQuestion.forNight(outlier, metric: .hrv, in: nights)
        )
        XCTAssertEqual(question.baseline, 50)
        XCTAssertEqual(question.baselineNightCount, 4)
        XCTAssertEqual(question.deviation, .above)
    }

    /// There is nothing to ask about a point that was never plotted.
    func testANightWithoutTheMetricHasNoQuestion() {
        let night = Fixture.night(daysAgo: 0, avgHRV: nil)
        XCTAssertNil(ChartQuestion.forNight(night, metric: .hrv, in: [night]))
    }

    func testASingleNightHasNoBaselineToCompareAgainst() throws {
        let night = Fixture.night(daysAgo: 0, avgHRV: 50)
        let question = try XCTUnwrap(ChartQuestion.forNight(night, metric: .hrv, in: [night]))
        XCTAssertEqual(question.baselineNightCount, 0)
        XCTAssertEqual(question.deviation, .unknown)
        XCTAssertTrue(question.nearby.isEmpty)
    }

    /// A whole month pasted into a prompt is not more context, it is the
    /// same context with the two nights that matter buried in it.
    func testOnlyTheNearestNeighboursAreListed() throws {
        let nights = (0...20).map { Fixture.night(daysAgo: $0, avgHRV: 50) }
        let question = try XCTUnwrap(
            ChartQuestion.forNight(nights[10], metric: .hrv, in: nights)
        )
        XCTAssertEqual(question.nearby.count, 4)
        let selected = nights[10].date
        for point in question.nearby {
            XCTAssertLessThanOrEqual(
                abs(point.date.timeIntervalSince(selected)),
                3 * 86_400,
                "a distant night was listed as nearby"
            )
        }
    }
    // MARK: - Vitals (V10.2 item 17)

    private var vitalPoints: [ChartQuestion.Point] {
        (0..<10).map {
            ChartQuestion.Point(
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 86_400),
                value: 54 + Double($0 % 3)
            )
        }
    }

    /// The gap this closes. `ChartQuestion` took a `TrendEngine.Metric`, which
    /// knows six series; the vitals screen charts seven, and only two overlap.
    /// Five of a person's body signals had a chart they could scrub and
    /// nothing they could ask about it.
    func testAVitalWithNoTrendEngineEquivalentCanStillBeAskedAbout() throws {
        let points = vitalPoints
        let question = try XCTUnwrap(
            ChartQuestion.forVital(
                .respiratoryRate,
                selected: points[5],
                in: points,
                baseline: 14.5,
                tolerance: 0.6,
                baselineNightCount: 21
            )
        )
        XCTAssertEqual(question.subject, .vital(.respiratoryRate))
        XCTAssertTrue(question.question.contains("respiratory rate"), question.question)
    }

    /// Title case is right for a panel heading and wrong mid-sentence.
    func testAVitalsLabelIsLowercasedInsideTheQuestion() throws {
        let points = vitalPoints
        let question = try XCTUnwrap(
            ChartQuestion.forVital(
                .oxygenSaturation, selected: points[2], in: points,
                baseline: 97, tolerance: 1, baselineNightCount: 21
            )
        )
        XCTAssertFalse(question.question.contains("Blood Oxygen"), question.question)
        XCTAssertTrue(question.question.contains("blood oxygen"), question.question)
    }

    /// The reason `Subject` is an enum over the two vocabularies rather than a
    /// struct of copied numbers: each is judged by its own screen's rule. A
    /// vital uses the tolerance `VitalsStatus` derived from the person's
    /// spread, so the same delta is notable at a tight tolerance and ordinary
    /// at a loose one.
    func testAVitalIsJudgedByItsOwnToleranceNotAFixedThreshold() throws {
        let points = vitalPoints
        func deviation(tolerance: Double) throws -> ChartQuestion.Deviation {
            let selected = ChartQuestion.Point(date: points[5].date, value: 60)
            let question = try XCTUnwrap(
                ChartQuestion.forVital(
                    .restingHeartRate,
                    selected: selected,
                    in: points.map { $0.date == selected.date ? selected : $0 },
                    baseline: 54, tolerance: tolerance, baselineNightCount: 21
                )
            )
            return question.deviation
        }
        XCTAssertEqual(try deviation(tolerance: 2), .above, "6 bpm over a 2 bpm tolerance is notable")
        XCTAssertEqual(try deviation(tolerance: 12), .typical, "6 bpm over a 12 bpm tolerance is not")
    }

    /// No tolerance means the vitals engine had too little history to
    /// establish one. That is "cannot say", not "unremarkable" -- reporting
    /// it as typical would claim a comparison that was never made.
    func testAVitalWithNoToleranceIsUnknownRatherThanTypical() throws {
        let points = vitalPoints
        let question = try XCTUnwrap(
            ChartQuestion.forVital(
                .wristTemperature, selected: points[3], in: points,
                baseline: 34.0, tolerance: nil, baselineNightCount: 3
            )
        )
        XCTAssertEqual(question.deviation, .unknown)
    }

    /// Trend metrics keep the rule they always had, shared with
    /// `ChangePointDetector`. The indirection must not have quietly changed
    /// what counts as notable on the screens that already worked.
    func testTrendMetricsStillUseTheSharedThreshold() {
        let night = Date(timeIntervalSince1970: 1_700_000_000)
        var small = ChartQuestion(subject: .trend(.hrv), selected: .init(date: night, value: 57))
        small.baseline = 55
        small.baselineNightCount = 21
        XCTAssertEqual(small.deviation, .typical, "under the 10% relative bar")

        var large = ChartQuestion(subject: .trend(.hrv), selected: .init(date: night, value: 70))
        large.baseline = 55
        large.baselineNightCount = 21
        XCTAssertEqual(large.deviation, .above)
    }

    /// Two subjects that share a raw metric name must not collide as ids --
    /// a sheet keyed on the id would otherwise fail to re-present when moving
    /// between the two screens.
    func testTrendAndVitalSubjectsDoNotShareAnIdentifier() {
        let night = Date(timeIntervalSince1970: 1_700_000_000)
        let trend = ChartQuestion(subject: .trend(.hrv), selected: .init(date: night, value: 55))
        let vital = ChartQuestion(subject: .vital(.hrv), selected: .init(date: night, value: 55))
        XCTAssertNotEqual(trend.id, vital.id)
    }

    /// A point the chart is not plotting is not a point to ask about.
    func testAPointOutsideTheSeriesProducesNoQuestion() {
        let points = vitalPoints
        XCTAssertNil(
            ChartQuestion.forVital(
                .hrv,
                selected: .init(date: Date(timeIntervalSince1970: 1), value: 55),
                in: points, baseline: 55, tolerance: 4, baselineNightCount: 21
            )
        )
    }

}
