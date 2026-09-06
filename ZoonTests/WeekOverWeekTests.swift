import XCTest

/// What counts as a change between two weeks.
///
/// The screens this replaces reported *any* non-zero delta as a change with a
/// good-or-bad colour on it. Two seven-night averages are essentially never
/// equal, so in practice every number was always announced as an improvement
/// or a regression -- including for a person whose sleep was not changing at
/// all.
final class WeekOverWeekTests: XCTestCase {

    /// Fourteen nights drawn from one distribution: two weeks that differ
    /// only by noise, so every "change" found in them is a false alarm by
    /// construction.
    private func steadyFortnight(
        duration: Double = 450, spread: Double = 50, hrv: Double = 55, seed: UInt64
    ) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<14).map { index in
            let asleep = duration + generator.nextDouble(in: -spread...spread)
            return Fixture.night(
                daysAgo: 14 - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9,
                avgHRV: hrv + generator.nextDouble(in: -8...8)
            )
        }.sorted { $0.date < $1.date }
    }

    /// A fortnight whose second week really is different: a large, sustained
    /// step in duration that any honest rule has to report.
    private func steppedFortnight(step: Double, seed: UInt64 = 5) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<14).map { index in
            let base = 400 + (index >= 7 ? step : 0)
            let asleep = base + generator.nextDouble(in: -12...12)
            return Fixture.night(
                daysAgo: 14 - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9,
                avgHRV: 55 + generator.nextDouble(in: -2...2)
            )
        }.sorted { $0.date < $1.date }
    }

    private func change(
        _ id: String, in nights: [SleepNightFeatures], goalMinutes: Double = 480
    ) throws -> WeekOverWeek.Change {
        let changes = WeekOverWeek.compare(nights: nights, goalMinutes: goalMinutes)
        return try XCTUnwrap(changes.first { $0.id == id }, "no \(id) comparison")
    }

    // MARK: - Noise is not a change

    /// The defect, stated as a rate. Across many steady fortnights, only a
    /// small share may be called a change -- and the old rule called every
    /// single one.
    func testASteadySleeperIsRarelyToldSomethingChanged() throws {
        var announced = 0
        let trials = 40
        for seed in 0..<UInt64(trials) {
            let nights = steadyFortnight(seed: seed &* 7 &+ 1)
            if try change("sleep", in: nights).isMeaningful { announced += 1 }
        }
        XCTAssertLessThan(
            announced, trials / 3,
            "\(announced) of \(trials) steady fortnights were reported as a change in duration"
        )
    }

    /// Neither half of the rule is enough on its own, and this is the one
    /// that is easy to get wrong: `clearsThreshold` was tuned for medians
    /// over a long window, where `ChangePointDetector` *also* requires the
    /// levels to separate. A fortnight can clear the threshold on noise
    /// alone, and the separation test is what catches it.
    func testAMoveThatClearsTheThresholdOnNoiseIsStillNotAChange() throws {
        // Wide night-to-night spread, no real shift: big deltas, no separation.
        var noisy = 0
        for seed in 0..<UInt64(40) {
            let nights = steadyFortnight(spread: 140, seed: seed &* 11 &+ 3)
            let sleep = try change("sleep", in: nights)
            if abs(sleep.delta) >= 15, sleep.separation < WeekOverWeek.minimumSeparation {
                XCTAssertFalse(
                    sleep.isMeaningful,
                    "a \(Int(sleep.delta))m delta at \(sleep.separation) SE was called a change"
                )
                noisy += 1
            }
        }
        XCTAssertGreaterThan(noisy, 0, "the fixture never produced the case under test")
    }

    /// A direction on a change that has not been shown to be one is the whole
    /// thing being fixed, so the flag is absent rather than false.
    func testAnUnconfirmedMoveCarriesNoDirection() throws {
        let nights = steadyFortnight(spread: 140, seed: 99)
        for change in WeekOverWeek.compare(nights: nights, goalMinutes: 480)
        where !change.isMeaningful {
            XCTAssertNil(change.isImprovement, "\(change.id) still carried a direction")
        }
    }

    // MARK: - A real change is still reported

    /// The other failure mode: a bar set so high that nothing is ever said.
    /// An hour more sleep every night for a week is not subtle.
    func testALargeSustainedStepIsReported() throws {
        let sleep = try change("sleep", in: steppedFortnight(step: 60))
        XCTAssertTrue(sleep.isMeaningful, "a 60-minute step was not reported")
        XCTAssertEqual(sleep.isImprovement, true)
        XCTAssertGreaterThan(sleep.separation, WeekOverWeek.minimumSeparation)
        XCTAssertEqual(sleep.delta, 60, accuracy: 12)
    }

    /// Direction follows the metric, not the sign. Less sleep is worse.
    func testASustainedDropIsReportedAsWorse() throws {
        let sleep = try change("sleep", in: steppedFortnight(step: -60))
        XCTAssertTrue(sleep.isMeaningful)
        XCTAssertEqual(sleep.isImprovement, false)
    }

    // MARK: - Which way is better

    /// Bedtime steadiness is a spread, so smaller is better -- the opposite
    /// of `TrendEngine.Metric.bedtime`, whose threshold it borrows. Getting
    /// this backwards would colour a scattered week green.
    func testTighterBedtimesAreAnImprovementNotARegression() throws {
        var generator = SeededGenerator(seed: 21)
        let nights = (0..<14).map { index -> SleepNightFeatures in
            // First week scattered, second week tight.
            let jitter = index < 7 ? generator.nextDouble(in: -75...75) : generator.nextDouble(in: -4...4)
            let inBed = 480 + jitter
            return Fixture.night(
                daysAgo: 14 - index,
                timeAsleepMinutes: inBed * 0.9,
                timeInBedMinutes: inBed
            )
        }.sorted { $0.date < $1.date }

        let bedtime = try change("bedtime", in: nights)
        XCTAssertLessThan(bedtime.after, bedtime.before, "the fixture must tighten, or this tests nothing")
        XCTAssertTrue(bedtime.isMeaningful)
        XCTAssertEqual(bedtime.isImprovement, true, "a steadier week was reported as a regression")
    }

    /// Sleep debt going down is an improvement, so its direction is inverted
    /// the same way.
    func testDebtIsBetterWhenItFalls() {
        let falling = WeekOverWeek.Change(
            metric: .sleepDebt, id: "debt", title: "Sleep debt",
            before: 300, after: 120, separation: 0, isMeaningful: true, higherIsBetter: false
        )
        XCTAssertEqual(falling.isImprovement, true)
    }

    // MARK: - Shape

    func testAPartialFortnightIsNotComparedAtAll() {
        let nights = Array(steadyFortnight(seed: 3).suffix(13))
        XCTAssertTrue(WeekOverWeek.compare(nights: nights, goalMinutes: 480).isEmpty)
    }

    func testTheComparisonsComeBackInAFixedOrder() {
        let ids = WeekOverWeek.compare(nights: steadyFortnight(seed: 4), goalMinutes: 480).map(\.id)
        XCTAssertEqual(Array(ids.prefix(3)), ["sleep", "hrv", "bedtime"])
    }

    /// Two weeks with no spread at all cannot be separated, and the guard
    /// must fail closed rather than divide by zero.
    func testNoSpreadMeansNoSeparationRatherThanInfinity() {
        let flat = Array(repeating: 450.0, count: 7)
        XCTAssertEqual(WeekOverWeek.separation(previous: flat, current: flat), 0)
        XCTAssertEqual(
            WeekOverWeek.separation(previous: flat, current: Array(repeating: 500.0, count: 7)), 0,
            "a difference with no variance to measure it against is not evidence"
        )
    }
}
