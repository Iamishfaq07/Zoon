import XCTest

/// Covers the reference-versus-recent redesign.
///
/// The engine these replace took one window, took its median, and compared
/// the single latest reading against it. A sustained shift therefore
/// contaminated its own reference — three weeks of a lower resting heart rate
/// dragged the 90-day median down with them — and "current" was one reading,
/// so a single bad night could produce a statement about a quarter of a year.
final class LongTermResilienceTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
    }

    /// `value(daysAgo:)` returning nil leaves that day unobserved.
    private func series(
        days: Int,
        every: Int = 1,
        value: (Int) -> Double?
    ) -> [LongTermResilience.Point] {
        stride(from: 0, to: days, by: every).compactMap { day in
            guard let value = value(day) else { return nil }
            return LongTermResilience.Point(
                date: calendar.date(byAdding: .day, value: -day, to: now)!,
                value: value
            )
        }
    }

    private func measure(
        _ spec: LongTermResilience.Spec,
        _ points: [LongTermResilience.Point],
        window: LongTermResilience.Window = .days90
    ) -> LongTermResilience.Signal {
        LongTermResilience.measure(
            spec: spec, points: points, window: window, now: now, calendar: calendar
        )
    }

    // MARK: - Not enough to say anything

    func testInsufficientHistoryDoesNotInventABaseline() {
        let signal = measure(
            .restingHeartRate,
            [LongTermResilience.Point(date: now, value: 54)]
        )
        XCTAssertNil(signal.referenceCenter)
        XCTAssertNil(signal.absoluteChange)
        XCTAssertEqual(signal.confidence, .insufficient)
        XCTAssertFalse(signal.isMeaningfulChange)
        XCTAssertFalse(signal.sentence.lowercased().contains("years"))
    }

    /// A full reference window with nothing recent is still nothing to say.
    func testAFullReferenceWithNoRecentDataSaysSo() {
        let signal = measure(.restingHeartRate, series(days: 90) { $0 < 14 ? nil : 54 })
        XCTAssertEqual(signal.confidence, .insufficient)
        XCTAssertNil(signal.referenceCenter)
        XCTAssertTrue(signal.sentence.contains("recent"), signal.sentence)
    }

    // MARK: - The contamination the redesign exists for

    /// Three weeks of a genuinely lower resting heart rate, compared against
    /// the days before them. The reference must not contain the shift.
    func testASustainedImprovementIsMeasuredAgainstAnUncontaminatedReference() throws {
        let signal = measure(.restingHeartRate, series(days: 90) { $0 < 21 ? 50 : 56 })

        XCTAssertEqual(try XCTUnwrap(signal.referenceCenter), 56, accuracy: 0.001,
                       "the reference window must exclude the recent shift entirely")
        XCTAssertEqual(try XCTUnwrap(signal.recentCenter), 50, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(signal.absoluteChange), -6, accuracy: 0.001)
        XCTAssertTrue(signal.isMeaningfulChange)
        XCTAssertEqual(signal.favourable, true)
        XCTAssertTrue(signal.sentence.contains("below"), signal.sentence)
        XCTAssertFalse(signal.sentence.lowercased().contains("younger"))
    }

    func testASustainedDeclineReportsTheUnfavourableSide() {
        let signal = measure(.restingHeartRate, series(days: 90) { $0 < 21 ? 58 : 50 })
        XCTAssertTrue(signal.isMeaningfulChange)
        XCTAssertEqual(signal.favourable, false)
        XCTAssertTrue(signal.sentence.contains("above"), signal.sentence)
    }

    /// A metric where higher is better exercises the other polarity, so the
    /// verdict cannot be a hard-coded side.
    func testHigherIsBetterSignalReversesTheVerdict() {
        let signal = measure(.heartRateVariability, series(days: 90) { $0 < 14 ? 40 : 62 })
        XCTAssertEqual(signal.favourable, false)
        XCTAssertTrue(signal.sentence.contains("below"), signal.sentence)
    }

    // MARK: - One reading is not a trend

    /// The failure the old design could not avoid: the latest value *was* the
    /// comparison, so one outlier moved everything.
    func testASingleOutlierDoesNotMoveTheComparison() {
        let signal = measure(.restingHeartRate, series(days: 90) { $0 == 0 ? 82 : 54 })
        XCTAssertFalse(signal.isMeaningfulChange, signal.sentence)
        XCTAssertNil(signal.favourable)
        XCTAssertTrue(signal.sentence.contains("stayed close"), signal.sentence)
    }

    /// Two loud nights in an otherwise steady fortnight still lose to the
    /// median of the fortnight.
    func testTwoOutliersInTheRecentWindowStillLoseToTheMedian() {
        let signal = measure(.restingHeartRate, series(days: 90) { $0 < 2 ? 78 : 54 })
        XCTAssertFalse(signal.isMeaningfulChange, signal.sentence)
    }

    // MARK: - Both gates

    /// Large in absolute terms, but ordinary for a signal that swings this
    /// much anyway. The robust-effect gate is what catches it.
    func testAChangeInsideTheSignalsOwnSwingIsNotAShift() throws {
        // The reference spreads evenly across 38/50/62/74/86, giving a
        // median of 62 and a MAD of 12 — a signal that genuinely swings this
        // much. Recent sits at 70, which is 8 ms up: past HRV's practical
        // threshold of 4, and well inside one MAD of the reference.
        let points = series(days: 90) { day in
            day < 14 ? 70 : 62 + (Double(day % 5) - 2) * 12
        }
        let signal = measure(.heartRateVariability, points)
        let effect = try XCTUnwrap(signal.robustEffect)
        XCTAssertLessThan(abs(effect), LongTermResilience.minimumRobustEffect)
        XCTAssertFalse(signal.isMeaningfulChange, signal.sentence)
    }

    /// Statistically unusual for a very steady signal, but too small to
    /// mean anything. The practical threshold is what catches this one.
    func testAStatisticallyUnusualButTinyChangeIsNotReported() throws {
        // Reference spreads across 54.5/55/55.5 — median 55, MAD 0.5 — and
        // recent sits at 56.2. That is 2.4 MADs, which is unusual, and 1.2
        // bpm, which is not worth a sentence.
        let points = series(days: 90) { day in
            day < 14 ? 56.2 : 55 + (Double(day % 3) - 1) * 0.5
        }
        let signal = measure(.restingHeartRate, points)
        XCTAssertGreaterThan(abs(try XCTUnwrap(signal.robustEffect)), LongTermResilience.minimumRobustEffect)
        XCTAssertLessThan(abs(try XCTUnwrap(signal.absoluteChange)), LongTermResilience.Spec.restingHeartRate.practicalThreshold)
        XCTAssertFalse(signal.isMeaningfulChange, signal.sentence)
    }

    /// A reference window with no spread at all cannot scale anything, so the
    /// practical threshold decides alone — and confidence is capped to say so.
    func testAFlatReferenceFallsBackToThePracticalThreshold() {
        let signal = measure(.restingHeartRate, series(days: 90) { $0 < 14 ? 60 : 54 })
        XCTAssertNil(signal.robustEffect)
        XCTAssertTrue(signal.isMeaningfulChange)
        XCTAssertLessThanOrEqual(signal.confidence, .moderate)
    }

    // MARK: - Shape of the change

    /// A gradual drift that has arrived is reported; the reference sits
    /// behind it, so the arrival is visible.
    func testGradualDriftIsVisibleOnceItHasArrived() {
        let signal = measure(.restingHeartRate, series(days: 90) { day in
            // 50 bpm ninety days ago rising steadily to 58 today.
            58 - Double(day) * 8.0 / 89.0
        })
        XCTAssertTrue(signal.isMeaningfulChange, signal.sentence)
        XCTAssertEqual(signal.favourable, false)
    }

    /// A step change is the easiest case and must not be missed.
    func testAStepChangeIsReported() {
        let signal = measure(.respiratoryRate, series(days: 90) { $0 < 14 ? 16.2 : 14.4 })
        XCTAssertTrue(signal.isMeaningfulChange, signal.sentence)
        XCTAssertEqual(signal.favourable, false)
    }

    /// A signal that moved and came back reads as unchanged, because it is.
    func testATrendThatReturnedToBaselineIsNotReported() {
        let signal = measure(.restingHeartRate, series(days: 90) { day in
            // Recent fortnight back at 54; the excursion sits in the middle
            // of the reference window, where it belongs.
            (20...40).contains(day) ? 62 : 54
        })
        XCTAssertFalse(signal.isMeaningfulChange, signal.sentence)
    }

    // MARK: - Sparse sampling and honest wording

    /// The wording the brief asks for. "For 8 days" reads as eight
    /// consecutive days; when eight readings are scattered across three
    /// weeks, that sentence is false.
    func testSparseSamplingIsDescribedAsObservationsSpanningDays() {
        XCTAssertEqual(
            LongTermResilience.coverage(8, spanDays: 19),
            "8 readings spanning 19 days"
        )
        XCTAssertEqual(LongTermResilience.coverage(14, spanDays: 14), "14 readings")
        XCTAssertEqual(LongTermResilience.coverage(1, spanDays: 1), "1 reading")
    }

    /// VO2 max arrives every few days at best, so its floors are lower — but
    /// the sentence still has to say how thin the evidence is.
    func testASparseSignalReportsItsSpanInTheSentence() {
        let signal = measure(.vo2Max, series(days: 90, every: 5) { _ in 44 }, window: .days90)
        XCTAssertTrue(signal.sentence.contains("spanning"), signal.sentence)
        XCTAssertLessThanOrEqual(signal.confidence, .low)
    }

    /// Sixty reference nights against four recent ones is not a
    /// well-observed fortnight, whatever the reference density says.
    func testConfidenceTakesTheThinnerOfTheTwoWindows() {
        let dense = measure(.restingHeartRate, series(days: 90) { _ in 54 })
        XCTAssertEqual(dense.confidence, .moderate,
                       "a perfectly flat series has no spread, which caps confidence")

        let thinRecent = measure(.restingHeartRate, series(days: 90) { day in
            guard day >= 14 || day % 3 == 0 else { return nil }
            return day % 2 == 0 ? 54 : 56
        })
        XCTAssertEqual(thinRecent.recentCount, 5)
        XCTAssertLessThanOrEqual(thinRecent.confidence, .moderate)
    }

    /// A missing stretch inside the reference window narrows the reference
    /// but must not shift the comparison onto the recent side.
    func testAMissingPeriodInsideTheReferenceDoesNotContaminateIt() throws {
        let signal = measure(.restingHeartRate, series(days: 90) { day in
            if day < 14 { return 50 }
            if (20...50).contains(day) { return nil }
            return 56
        })
        XCTAssertEqual(try XCTUnwrap(signal.referenceCenter), 56, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(signal.recentCenter), 50, accuracy: 0.001)
    }

    // MARK: - Per-signal thresholds

    /// The same 3 ms move is noise for HRV and a real shift for resting heart
    /// rate. One generic tolerance could not tell them apart, which is why
    /// there no longer is one.
    func testEachSignalCarriesItsOwnPracticalThreshold() {
        XCTAssertGreaterThan(
            LongTermResilience.Spec.heartRateVariability.practicalThreshold,
            LongTermResilience.Spec.restingHeartRate.practicalThreshold
        )
        XCTAssertLessThan(
            LongTermResilience.Spec.respiratoryRate.practicalThreshold,
            LongTermResilience.Spec.restingHeartRate.practicalThreshold
        )
        XCTAssertLessThan(
            LongTermResilience.Spec.vo2Max.minimumReference,
            LongTermResilience.Spec.restingHeartRate.minimumReference
        )
    }

    /// The reference window sits *before* the recent one, so the shortest
    /// window still needs more history than its label suggests. Worth
    /// asserting: getting this backwards is how the contamination returns.
    func testTheReferenceWindowEndsWhereTheRecentWindowBegins() throws {
        let signal = measure(
            .restingHeartRate,
            series(days: 40) { $0 < 7 ? 50 : 56 },
            window: .days30
        )
        XCTAssertEqual(try XCTUnwrap(signal.referenceCenter), 56, accuracy: 0.001)
        XCTAssertEqual(signal.recentCount, 7)
    }
}
