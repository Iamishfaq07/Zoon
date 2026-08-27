import XCTest

final class ChangePointDetectorTests: XCTestCase {

    /// Builds a series where duration holds `before` for the oldest
    /// `beforeCount` nights and `after` for the newest `afterCount`.
    ///
    /// Noise comes from `SeededGenerator` rather than an alternating +/-
    /// pattern: a strictly alternating series makes each segment's median
    /// jump to one extreme or the other depending on whether the segment has
    /// an odd or even length, which manufactures a large median gap out of
    /// pure noise. Seeded means deterministic, so this is still reproducible.
    ///
    /// `timeInBed` is scaled to hold efficiency fixed. `Fixture.night`
    /// derives `sleepEfficiencyPercent` from asleep/inBed, so varying
    /// duration alone would silently move efficiency too.
    private func steppedNights(
        beforeCount: Int, afterCount: Int,
        before: Double, after: Double,
        wobble: Double = 8,
        seed: UInt64 = 42
    ) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        // Draw in a fixed order (oldest first) so the seed maps to the same
        // night every run regardless of how the fixture sorts afterwards.
        let total = beforeCount + afterCount
        let nudges = (0..<total).map { _ in
            wobble == 0 ? 0 : generator.nextDouble(in: -wobble...wobble)
        }

        return (0..<total).map { indexFromOldest in
            let daysAgo = total - indexFromOldest
            let base = indexFromOldest < beforeCount ? before : after
            let asleep = base + nudges[indexFromOldest]
            return Fixture.night(
                daysAgo: daysAgo,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Finding the point

    func testDetectsAStepChangeAndDatesItAtTheFirstNightOfTheNewLevel() throws {
        let nights = steppedNights(beforeCount: 20, afterCount: 20, before: 400, after: 480)

        let result = try XCTUnwrap(
            ChangePointDetector.detect(nights: nights, metric: .duration)
        )

        XCTAssertEqual(result.beforeMedian, 400, accuracy: 6)
        XCTAssertEqual(result.afterMedian, 480, accuracy: 6)
        XCTAssertTrue(result.isImprovement, "more sleep is an improvement for duration")

        // The reported date should land on the true step (index 20 of 40),
        // give or take a night. Not exact: with realistic noise the split
        // that maximises separation can sit one or two nights either side of
        // the real one, because a borderline night pulls slightly harder on
        // one segment's median than the other. Demanding the exact index
        // would be asserting a precision the estimator does not have.
        let sorted = nights.sorted { $0.date < $1.date }
        let detectedIndex = try XCTUnwrap(sorted.firstIndex { $0.date == result.date })
        XCTAssertEqual(Double(detectedIndex), 20, accuracy: 2)
    }

    /// The whole reason this exists alongside `TrendEngine`: a shift that
    /// happened well before the recent window is invisible to a fixed
    /// two-window comparison, because it sits entirely inside both windows.
    func testFindsAShiftThatIsOlderThanTrendEngineSWindows() throws {
        // Change 30 nights back, then 30 stable nights. TrendEngine's default
        // 14+14 only ever looks at the newest 28, all of which are post-change.
        let nights = steppedNights(beforeCount: 30, afterCount: 30, before: 380, after: 470)

        XCTAssertTrue(
            TrendEngine.detect(nights: nights).allSatisfy { $0.metric != .duration },
            "precondition: the fixed-window comparison should see no duration change here"
        )

        let result = try XCTUnwrap(
            ChangePointDetector.detect(nights: nights, metric: .duration)
        )
        XCTAssertEqual(result.beforeMedian, 380, accuracy: 6)
        XCTAssertEqual(result.afterMedian, 470, accuracy: 6)
    }

    // MARK: - Not firing on noise

    func testStableHistoryReportsNoChangePoint() {
        let nights = steppedNights(beforeCount: 25, afterCount: 25, before: 450, after: 450)
        XCTAssertNil(ChangePointDetector.detect(nights: nights, metric: .duration))
    }

    /// A shift smaller than the metric's own reporting threshold is real but
    /// not worth a sentence -- and that threshold is shared with `TrendEngine`
    /// rather than re-tuned here.
    func testShiftBelowTheMetricThresholdIsNotReported() {
        // 8 minutes, under .duration's 15-minute floor, with near-zero noise
        // so it would otherwise clear the effect-size bar easily.
        let nights = steppedNights(beforeCount: 20, afterCount: 20, before: 450, after: 458, wobble: 0.5)
        XCTAssertNil(ChangePointDetector.detect(nights: nights, metric: .duration))
    }

    /// A large step buried in even larger night-to-night swings is not a
    /// level change, it is noise -- the effect size is what rejects it.
    func testLargeSwingsWithNoLevelChangeReportNothing() {
        let nights = steppedNights(beforeCount: 25, afterCount: 25, before: 450, after: 450, wobble: 90)
        XCTAssertNil(ChangePointDetector.detect(nights: nights, metric: .duration))
    }

    // MARK: - Sample-size guards

    func testTooFewNightsReturnsNil() {
        // 13 total: cannot give 7 to each side of any split.
        let nights = steppedNights(beforeCount: 6, afterCount: 7, before: 380, after: 480)
        XCTAssertNil(ChangePointDetector.detect(nights: nights, metric: .duration))
    }

    /// A change in the last few nights has too little "after" to be a level
    /// yet. It should stay unreported until it persists.
    func testAChangeTooCloseToTheEndIsNotYetALevel() {
        let nights = steppedNights(beforeCount: 30, afterCount: 3, before: 380, after: 480)
        XCTAssertNil(ChangePointDetector.detect(nights: nights, metric: .duration))
    }

    func testNightsMissingTheMetricAreDroppedNotInterpolated() throws {
        // Every night carries duration; only HRV is missing on all of them.
        let nights = Fixture.consecutiveNights(40) { daysAgo in
            Fixture.night(daysAgo: daysAgo, avgHRV: nil)
        }
        XCTAssertNil(
            ChangePointDetector.detect(nights: nights, metric: .hrv),
            "a metric with no samples at all cannot have a change point"
        )
    }

    // MARK: - detectAll

    func testDetectAllIncludesTheShiftedMetric() {
        let nights = steppedNights(beforeCount: 20, afterCount: 20, before: 400, after: 480)
        XCTAssertTrue(ChangePointDetector.detectAll(nights: nights).contains { $0.metric == .duration })
    }

    func testDetectAllOnStableHistoryReturnsEmpty() {
        let nights = steppedNights(beforeCount: 25, afterCount: 25, before: 450, after: 450)
        XCTAssertEqual(ChangePointDetector.detectAll(nights: nights), [])
    }

    func testDetectAllSortsByEffect() {
        let nights = steppedNights(beforeCount: 20, afterCount: 20, before: 400, after: 480)
        let effects = ChangePointDetector.detectAll(nights: nights).map(\.effect)
        XCTAssertEqual(effects, effects.sorted(by: >))
    }

    // MARK: - Copy

    func testSentenceNamesTheDirectionAndCarriesADate() throws {
        let nights = steppedNights(beforeCount: 20, afterCount: 20, before: 480, after: 400)
        let result = try XCTUnwrap(ChangePointDetector.detect(nights: nights, metric: .duration))

        XCTAssertTrue(result.sentence.contains("fell"), result.sentence)
        XCTAssertTrue(result.sentence.contains("starting around"), result.sentence)
        XCTAssertFalse(result.isImprovement)
    }
}
