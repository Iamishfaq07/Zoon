import XCTest

/// §22. The engine's job is to draw bands only where there are nights to draw
/// them from, and to keep three answers distinct that most apps collapse into
/// two: an association, a ruled-out difference, and "we cannot tell".
final class SensitivityCurveTests: XCTestCase {

    private let dose = SensitivityCurve.Dose(
        behaviour: "Test dose",
        unit: "mg",
        bands: [
            SensitivityCurve.Band(label: "Low", lower: 0, upper: 100),
            SensitivityCurve.Band(label: "High", lower: 100, upper: nil)
        ]
    )

    /// Deliberately clear-cut values rather than random ones: the bootstrap is
    /// deterministic, but a test that depended on its exact bounds would be
    /// pinned to the generator rather than to the behaviour.
    private let quiet: [Double] = [12, 13, 14, 14, 15, 13, 16, 12, 14, 15,
                                   13, 14, 15, 12, 16, 14, 13, 15, 14, 13]

    private func observations(
        low: [Double], high: [Double]
    ) -> [SensitivityCurve.Observation] {
        low.map { SensitivityCurve.Observation(dose: 50, outcome: $0) }
            + high.map { SensitivityCurve.Observation(dose: 150, outcome: $0) }
    }

    private func reading(
        _ curve: SensitivityCurve.Curve, _ label: String
    ) -> SensitivityCurve.Reading? {
        curve.readings.first { $0.band.label == label }
    }

    // MARK: - Bands

    func testABandIncludesItsLowerEdgeAndExcludesItsUpper() {
        let band = SensitivityCurve.Band(label: "x", lower: 100, upper: 200)
        XCTAssertTrue(band.contains(100))
        XCTAssertTrue(band.contains(199.9))
        XCTAssertFalse(band.contains(200))
        XCTAssertFalse(band.contains(99.9))
    }

    func testAnOpenTopBandHasNoUpperEdge() {
        let band = SensitivityCurve.Band(label: "x", lower: 200, upper: nil)
        XCTAssertTrue(band.contains(200))
        XCTAssertTrue(band.contains(100_000))
    }

    /// The shipped bands must tile their range — a dose falling through a gap
    /// would silently vanish from the curve it belongs to.
    func testTheShippedBandsLeaveNoGaps() {
        for dose in [
            SensitivityCurve.lateCaffeine,
            SensitivityCurve.napDuration,
            SensitivityCurve.napTiming
        ] {
            for (index, band) in dose.bands.enumerated().dropLast() {
                let next = dose.bands[index + 1]
                XCTAssertEqual(
                    band.upper, next.lower,
                    "\(dose.behaviour): \(band.label) does not meet \(next.label)"
                )
            }
        }
    }

    /// Tiling is not enough on its own: `napTiming` tiled perfectly and still
    /// stopped at 18:00, so every evening nap fell off the end of it. A closed
    /// top band is a silent discard, which is the one failure mode this whole
    /// engine is built to avoid.
    func testEveryShippedDoseIsOpenAtOneEnd() {
        for dose in [
            SensitivityCurve.lateCaffeine,
            SensitivityCurve.napDuration,
            SensitivityCurve.napTiming,
            SensitivityCurve.workoutTiming
        ] {
            XCTAssertTrue(
                dose.bands.contains { $0.upper == nil },
                "\(dose.behaviour) has no open band, so a large enough dose has nowhere to go"
            )
        }
    }

    /// §10. Every hour of the day lands in exactly one nap-timing band. What
    /// makes something a nap is the episode architecture's decision — see
    /// `SensitivityCurve.napTiming` — and once it has made it, the hour may
    /// not quietly overrule it.
    func testEveryNapHourLandsInExactlyOneBand() {
        for hour in 0..<24 {
            let matches = SensitivityCurve.napTiming.bands.filter { $0.contains(Double(hour)) }
            XCTAssertEqual(matches.count, 1, "hour \(hour) matched \(matches.map(\.label))")
        }
    }

    /// The six cases the brief names, by the hour each one starts.
    func testTheNamedNapHoursLandWhereTheyShould() {
        func band(_ hour: Double) -> String? {
            SensitivityCurve.napTiming.bands.first { $0.contains(hour) }?.label
        }
        XCTAssertEqual(band(11), "Morning")              // 11 AM nap
        XCTAssertEqual(band(14), "Early afternoon")      // 2 PM nap
        XCTAssertEqual(band(17), "Late afternoon")       // 5 PM nap
        XCTAssertEqual(band(19), "Evening")              // 7 PM short nap
        XCTAssertEqual(band(20), "Evening")              // 8 PM, if classified a nap
        XCTAssertEqual(band(22.5), "Evening")            // late nap near bedtime
    }

    /// The defect, stated as behaviour rather than as a table: an evening nap
    /// reaches the curve and is compared, instead of vanishing.
    func testAnEveningNapIsCurvedRatherThanDiscarded() throws {
        let observations =
            quiet.map { SensitivityCurve.Observation(dose: 14, outcome: $0) }
            + quiet.map { SensitivityCurve.Observation(dose: 19.5, outcome: $0 + 30) }
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: SensitivityCurve.napTiming,
                outcome: .sleepOnset,
                observations: observations
            )
        )
        let evening = try XCTUnwrap(curve.readings.first { $0.band.label == "Evening" })
        XCTAssertEqual(evening.nights, quiet.count)
        XCTAssertEqual(evening.verdict, .associated(higher: true))
    }

    /// A night-shift worker's main sleep beginning at 08:00 is not made a nap
    /// by landing in the morning band. Nothing in this table decides that —
    /// only episodes already typed `.nap` are ever handed to it — and the
    /// morning band exists for the person who naps at 11 AM.
    func testTheMorningBandCoversTheShiftWorkersHourWithoutClaimingIt() {
        XCTAssertTrue(SensitivityCurve.napTiming.bands.first?.contains(8) == true)
    }

    // MARK: - The three answers

    /// Two groups drawn from the same nights. The interval sits inside what
    /// would matter to anybody, so a meaningful difference has been ruled out
    /// — which is a stronger statement than "uncertain", and the one the
    /// brief's own example makes for its first band.
    func testIdenticalBandsReadAsLittleObservedDifference() throws {
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: dose,
                outcome: .sleepOnset,
                observations: observations(low: quiet, high: quiet)
            )
        )
        let high = try XCTUnwrap(reading(curve, "High"))
        XCTAssertEqual(high.verdict, .littleDifference)
        XCTAssertEqual(high.sentence(outcome: .sleepOnset), "little observed difference")
        XCTAssertFalse(curve.foundAnAssociation)
    }

    func testAClearShiftReadsAsAnAssociationWithItsSize() throws {
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: dose,
                outcome: .sleepOnset,
                observations: observations(low: quiet, high: quiet.map { $0 + 30 })
            )
        )
        let high = try XCTUnwrap(reading(curve, "High"))
        XCTAssertEqual(high.verdict, .associated(higher: true))
        XCTAssertEqual(
            high.sentence(outcome: .sleepOnset),
            "later sleep onset associated, about 30 min"
        )
        XCTAssertTrue(curve.foundAnAssociation)
    }

    func testAShiftTheOtherWayIsNamedTheOtherWay() throws {
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: dose,
                outcome: .sleepOnset,
                observations: observations(low: quiet.map { $0 + 30 }, high: quiet)
            )
        )
        let high = try XCTUnwrap(reading(curve, "High"))
        XCTAssertEqual(high.verdict, .associated(higher: false))
        XCTAssertTrue(
            high.sentence(outcome: .sleepOnset).contains("earlier sleep onset associated"),
            high.sentence(outcome: .sleepOnset)
        )
    }

    /// Six wildly scattered nights. The interval spans zero *and* is far too
    /// wide to rule anything out, so the honest answer is neither "no effect"
    /// nor an association.
    func testAWideIntervalSpanningZeroIsUncertainRatherThanNoEffect() throws {
        let scattered: [Double] = [2, 45, 8, 60, 15, 38]
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: dose,
                outcome: .sleepOnset,
                observations: observations(low: quiet, high: scattered)
            )
        )
        let high = try XCTUnwrap(reading(curve, "High"))
        XCTAssertEqual(high.verdict, .uncertain)
        XCTAssertEqual(high.sentence(outcome: .sleepOnset), "uncertain")
    }

    /// The distinction the whole engine turns on: "we ruled it out" and "we
    /// could not tell" must never be the same string.
    func testLittleDifferenceAndUncertainAreDifferentAnswers() {
        let ruledOut = SensitivityCurve.verdict(interval: (-4, 5), outcome: .sleepOnset)
        let cannotTell = SensitivityCurve.verdict(interval: (-40, 35), outcome: .sleepOnset)
        XCTAssertEqual(ruledOut, .littleDifference)
        XCTAssertEqual(cannotTell, .uncertain)
        XCTAssertNotEqual(
            SensitivityCurve.Reading(
                band: dose.bands[1], nights: 9, median: 1, difference: 1,
                intervalLower: -4, intervalUpper: 5, verdict: ruledOut
            ).sentence(outcome: .sleepOnset),
            SensitivityCurve.Reading(
                band: dose.bands[1], nights: 9, median: 1, difference: 1,
                intervalLower: -40, intervalUpper: 35, verdict: cannotTell
            ).sentence(outcome: .sleepOnset)
        )
    }

    func testAnIntervalTouchingZeroFromAboveIsStillNotAnAssociation() {
        XCTAssertNotEqual(
            SensitivityCurve.verdict(interval: (0, 12), outcome: .sleepOnset),
            .associated(higher: true)
        )
    }

    /// The practical threshold is per outcome. The same interval that rules a
    /// difference out for sleep duration leaves it open for onset.
    func testThePracticalThresholdIsTheOutcomesOwn() {
        let interval = (lower: -15.0, upper: 15.0)
        XCTAssertEqual(SensitivityCurve.verdict(interval: interval, outcome: .asleepMinutes), .littleDifference)
        XCTAssertEqual(SensitivityCurve.verdict(interval: interval, outcome: .sleepOnset), .uncertain)
    }

    // MARK: - Refusals

    func testABandWithTooFewNightsSaysSoRatherThanBeingEstimated() throws {
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: SensitivityCurve.Dose(
                    behaviour: "Test", unit: "mg",
                    // Not `dose.bands + ...`: the shared fixture's top band is
                    // open, so a 2,000 dose would land in both it and the new
                    // one, and the sparse band would not be sparse.
                    bands: [
                        SensitivityCurve.Band(label: "Low", lower: 0, upper: 100),
                        SensitivityCurve.Band(label: "High", lower: 100, upper: 1_000),
                        SensitivityCurve.Band(label: "Very high", lower: 1_000, upper: nil)
                    ]
                ),
                outcome: .sleepOnset,
                observations: observations(low: quiet, high: quiet)
                    + [SensitivityCurve.Observation(dose: 2_000, outcome: 30)]
            )
        )
        let sparse = try XCTUnwrap(reading(curve, "Very high"))
        XCTAssertEqual(sparse.verdict, .tooFew)
        XCTAssertNil(sparse.median)
        XCTAssertNil(sparse.intervalLower)
        XCTAssertEqual(sparse.sentence(outcome: .sleepOnset), "not enough nights yet")
    }

    /// One group is not a curve. Drawing it alone invites the reader to
    /// compare it against nothing.
    func testASingleQualifyingBandIsNotACurve() {
        XCTAssertNil(
            SensitivityCurve.build(
                dose: dose,
                outcome: .sleepOnset,
                observations: observations(low: quiet, high: [14, 15])
            )
        )
    }

    func testNoObservationsIsNoCurve() {
        XCTAssertNil(
            SensitivityCurve.build(dose: dose, outcome: .sleepOnset, observations: [])
        )
    }

    // MARK: - The reference band

    func testTheFirstQualifyingBandBecomesTheComparison() throws {
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: dose,
                outcome: .sleepOnset,
                observations: observations(low: quiet, high: quiet)
            )
        )
        XCTAssertEqual(reading(curve, "Low")?.verdict, .reference)
        XCTAssertEqual(
            reading(curve, "Low")?.sentence(outcome: .sleepOnset), "your comparison band"
        )
        XCTAssertNil(reading(curve, "Low")?.intervalLower)
    }

    /// Workout timing declares its bands furthest-from-bed first on purpose:
    /// the control is the workout that finished long before bed, not the one
    /// closest to it.
    func testWorkoutTimingComparesAgainstTheWorkoutFurthestFromBed() {
        XCTAssertEqual(SensitivityCurve.workoutTiming.bands.first?.label, "Over 6 hours before")
    }

    // MARK: - Determinism

    /// A stated confidence that reshuffles between two visits to the same
    /// screen is worse than no confidence at all.
    func testTheSameNightsAlwaysProduceTheSameInterval() throws {
        let data = observations(low: quiet, high: quiet.map { $0 + 8 })
        let first = try XCTUnwrap(
            SensitivityCurve.build(dose: dose, outcome: .sleepOnset, observations: data)
        )
        let second = try XCTUnwrap(
            SensitivityCurve.build(dose: dose, outcome: .sleepOnset, observations: data)
        )
        XCTAssertEqual(first, second)
    }

    // MARK: - What it will not build

    /// The gaps are named in the app rather than only in a document, because a
    /// missing curve with no explanation reads as a feature that does not work.
    func testTheDimensionsThatCannotBeBuiltAreNamedWithTheirReason() {
        let behaviours = SensitivityCurve.unavailable.map(\.behaviour)
        XCTAssertTrue(behaviours.contains("Caffeine timing"))
        XCTAssertTrue(behaviours.contains("Light timing"))
        XCTAssertTrue(behaviours.contains("Workout load"))
        for entry in SensitivityCurve.unavailable {
            XCTAssertFalse(entry.reason.isEmpty, entry.behaviour)
        }
    }

    // MARK: - Language

    func testNothingInACurveImpliesCause() throws {
        let curve = try XCTUnwrap(
            SensitivityCurve.build(
                dose: dose,
                outcome: .sleepOnset,
                observations: observations(low: quiet, high: quiet.map { $0 + 30 })
            )
        )
        // The caveat is checked separately and deliberately not by the
        // causation guard, for the same reason the Awakening Inspector's is:
        // it is the one line that names cause, in order to deny it. A blanket
        // "must not contain causes" would fail on exactly the sentence that
        // makes the claim safe.
        XCTAssertTrue(curve.caveat.contains("not causes"), curve.caveat)

        var lines = curve.readings.map { $0.sentence(outcome: curve.outcome) }
        lines.append(contentsOf: SensitivityCurve.unavailable.map(\.reason))

        for line in lines {
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
            for banned in ["causes", "makes you", "leads to", "proves"] {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
        }
    }
}
