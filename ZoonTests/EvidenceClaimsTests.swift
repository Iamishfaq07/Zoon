import XCTest

/// Who is allowed to write in the ledger, and under what name.
///
/// Two properties matter more than any individual sentence these produce.
///
/// **Identity is total.** A claim's history is every revision sharing its
/// identifier, so an identifier that collides merges two beliefs into one
/// timeline that reads as a single thing changing its mind, and an identifier
/// that drifts splits one belief into two histories that each look complete.
/// Neither failure shows up as a crash or a wrong number -- it shows up as a
/// plausible story about the wrong thing.
///
/// **Standing is not interchangeable.** A pre-specified experiment, a
/// matched-pair association and a contrast between two groups of the person's
/// own nights are three different strengths of evidence. The ledger is the
/// one screen that puts them side by side, which makes it the one place a
/// scan could quietly borrow an experiment's authority.
final class EvidenceClaimsTests: XCTestCase {

    private let everyClaim: [EvidenceLedger.Claim] = [
        .sleepMap(x: "bedtime", y: "duration", outcome: "hrv"),
        .twin(lever: "duration", direction: "more", outcome: "hrv"),
        .changePoint(metric: "restingHeartRate"),
        .behaviour(tag: "alcohol"),
        .experiment(tag: "alcohol")
    ]

    // MARK: - Identity

    func testEveryClaimSurvivesItsOwnIdentifier() {
        for claim in everyClaim {
            XCTAssertEqual(EvidenceLedger.Claim.parse(claim.id), claim, claim.id)
        }
    }

    /// The collision that would matter most: the same behaviour has both an
    /// association and an experiment, and they are different claims about it.
    /// Merging their timelines would let the association supply the answer
    /// the experiment was supposed to earn.
    func testAnAssociationAndAnExperimentOnOneTagAreTwoClaims() {
        XCTAssertNotEqual(
            EvidenceLedger.Claim.behaviour(tag: "alcohol").id,
            EvidenceLedger.Claim.experiment(tag: "alcohol").id
        )
    }

    func testNoTwoClaimsShareAnIdentifier() {
        let ids = everyClaim.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "\(ids)")
    }

    /// The existing ledger identifiers were written as `tag:<rawValue>`, and
    /// every revision already recorded carries that string. Changing it here
    /// would orphan all of them -- the histories would still be in the store
    /// and nothing would ever find them again.
    func testTheBehaviourIdentifierIsUnchangedFromBeforeThisTypeExisted() {
        XCTAssertEqual(EvidenceLedger.Claim.behaviour(tag: "caffeineLate").id, "tag:caffeineLate")
    }

    /// A kind a later release stops writing must not decode as some other
    /// kind. Callers fall back to the stored headline, which is kept verbatim
    /// for exactly this reason.
    func testAnUnknownIdentifierParsesAsNothingRatherThanAsSomethingElse() {
        XCTAssertNil(EvidenceLedger.Claim.parse("dreamJournal:lucid"))
        XCTAssertNil(EvidenceLedger.Claim.parse("tag"))
        XCTAssertNil(EvidenceLedger.Claim.parse("tag:alcohol:extra"))
        XCTAssertNil(EvidenceLedger.Claim.parse(""))
    }

    // MARK: - Standing

    func testTheHierarchyRunsFromScanToExperiment() {
        let ordered = everyClaim.sorted { $0.tier < $1.tier }
        XCTAssertEqual(ordered.map(\.kindLabel), [
            "Sleep map", "Night comparison", "Change over time", "Cause Finder", "Experiment"
        ])
    }

    func testAnObservationRanksBelowAnAssociation() {
        XCTAssertLessThan(
            EvidenceLedger.Claim.twin(lever: "duration", direction: "more", outcome: "hrv").tier,
            EvidenceLedger.Claim.behaviour(tag: "alcohol").tier
        )
    }

    // MARK: - Change points

    private func changePoint(
        metric: TrendEngine.Metric = .restingHeartRate,
        daysAgo: Int = 20,
        before: Double = 52,
        after: Double = 58
    ) -> ChangePointDetector.Result {
        ChangePointDetector.Result(
            metric: metric,
            date: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400),
            beforeMedian: before,
            afterMedian: after,
            beforeNights: 21,
            afterNights: 14,
            effect: 4.1
        )
    }

    /// A change point is a level that moved. Nothing about detecting it
    /// controls for anything, so it cannot be recorded at the strength of a
    /// matched-pair association.
    func testAChangePointIsRecordedAsObservedNotAssociated() {
        let revision = EvidenceLedger.revision(for: changePoint())
        XCTAssertEqual(revision.status, .observed)
        XCTAssertEqual(revision.provenance, "ChangePointDetector")
        XCTAssertEqual(revision.effect, 6)
        XCTAssertEqual(revision.effectUnit, "bpm")
        XCTAssertEqual(revision.sampleSize, 35)
    }

    /// The whole reason the claim is keyed by metric alone. As more nights
    /// arrive the detector can move the shift's date, and that is Zoon
    /// revising a belief it already holds -- not a second, unrelated belief
    /// with an empty history beside the first.
    func testARedatedShiftRevisesTheSameClaimRatherThanStartingANewOne() {
        let first = EvidenceLedger.revision(for: changePoint(daysAgo: 20, after: 58))
        let second = EvidenceLedger.revision(for: changePoint(daysAgo: 14, after: 61))
        XCTAssertEqual(first.claimID, second.claimID)

        let history = EvidenceLedger.recording(second, into: [first])
        XCTAssertEqual(EvidenceLedger.timeline(for: first.claimID, in: history).count, 2)
    }

    /// The detector reports separation in standard errors, not an interval on
    /// the difference. Deriving one from the effect would be inventing a
    /// precision it never computed.
    func testAChangePointCarriesNoFabricatedInterval() {
        let revision = EvidenceLedger.revision(for: changePoint())
        XCTAssertNil(revision.uncertaintyLower)
        XCTAssertNil(revision.uncertaintyUpper)
    }

    // MARK: - Twin splits

    /// Nights where longer sleep genuinely coincides with higher HRV, so
    /// `ZoonTwin` has a real split to find. Deliberately the same shape
    /// `ZoonTwinTests` uses, so a change that breaks the engine breaks both.
    private func coupledNights(_ count: Int = 40, seed: UInt64 = 31) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let asleep = 450 + generator.nextDouble(in: -90...90)
            let hrv = 55 + (asleep - 450) * 0.05 + generator.nextDouble(in: -3...3)
            return Fixture.night(
                daysAgo: count - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9,
                avgHRV: hrv
            )
        }.sorted { $0.date < $1.date }
    }

    func testATwinSplitIsRecordedAsObserved() throws {
        let projection = try XCTUnwrap(
            ZoonTwin.project(
                nights: coupledNights(60), lever: .duration, direction: .more, outcome: .hrv
            )
        )
        XCTAssertGreaterThanOrEqual(
            projection.confidence, EvidenceLedger.twinMinimumConfidence,
            "fixture must clear the bar, or this test is asserting on the refusal path"
        )

        let revision = try XCTUnwrap(EvidenceLedger.revision(for: projection))
        XCTAssertEqual(revision.status, .observed)
        XCTAssertEqual(revision.provenance, "ZoonTwin")
        XCTAssertEqual(revision.claimID, "twin:duration:more:hrv")
        XCTAssertEqual(revision.effectUnit, "ms")
    }

    /// A contrast is only as strong as its thinner side. Recording the total
    /// would make a lopsided split look like far more evidence than it is.
    func testATwinSplitRestsOnItsSmallerGroup() throws {
        let projection = try XCTUnwrap(
            ZoonTwin.project(
                nights: coupledNights(60), lever: .duration, direction: .more, outcome: .hrv
            )
        )
        let revision = try XCTUnwrap(EvidenceLedger.revision(for: projection))
        XCTAssertEqual(revision.sampleSize, min(projection.leverNights, projection.otherNights))
        XCTAssertLessThan(revision.sampleSize, projection.leverNights + projection.otherNights)
    }

    /// The screen may draw a thin split as thin. The ledger is a record of
    /// what Zoon believed, and a number it would not stand behind is not a
    /// belief.
    func testASplitTooThinToStandBehindIsNotRecorded() throws {
        // Few enough nights that the smaller group lands in `ZoonTwin`'s
        // `.low` band -- above its own seven-night floor, below the bar the
        // ledger sets.
        let projection = try XCTUnwrap(
            ZoonTwin.project(
                nights: coupledNights(28), lever: .duration, direction: .more, outcome: .hrv
            )
        )
        XCTAssertLessThan(
            projection.confidence, EvidenceLedger.twinMinimumConfidence,
            "fixture must be below the bar, or this test is asserting on the recording path"
        )
        XCTAssertNil(EvidenceLedger.revision(for: projection))
    }

    // MARK: - The sleep map

    /// A balanced 3x3 with one visibly better cell, so the winner is known in
    /// advance. Same shape as `SleepMapTests`' own fixture, and on the same
    /// axes: `Fixture.night` derives bedtime from time in bed, so bedtime and
    /// duration are perfectly collinear in a fixture and cannot fill a grid
    /// between them. What is being tested here is the recording, not the
    /// binning -- `SleepMapTests` owns that -- and the map the app actually
    /// draws is pinned separately below.
    private func gridNights(perCell: Int = 5, standoutHRV: Double = 70) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: 17)
        var nights: [SleepNightFeatures] = []
        var day = 0
        for (xIndex, asleep) in [360.0, 450.0, 540.0].enumerated() {
            for (yIndex, rhr) in [48.0, 54.0, 60.0].enumerated() {
                for _ in 0..<perCell {
                    day += 1
                    let duration = asleep + generator.nextDouble(in: -12...12)
                    let isStandout = xIndex == 0 && yIndex == 2
                    nights.append(Fixture.night(
                        daysAgo: day,
                        timeAsleepMinutes: duration,
                        timeInBedMinutes: duration / 0.9,
                        avgHRV: (isStandout ? standoutHRV : 52) + generator.nextDouble(in: -1...1),
                        restingHeartRate: rhr + generator.nextDouble(in: -2...2)
                    ))
                }
            }
        }
        return nights.sorted { $0.date < $1.date }
    }

    private func builtMap(_ nights: [SleepNightFeatures]) throws -> SleepMap.Map {
        try XCTUnwrap(
            SleepMap.build(
                nights: nights, xAxis: .duration, yAxis: .restingHeartRate, outcome: .hrv
            )
        )
    }

    /// The one configuration the app draws and the coordinator records. Two
    /// axes a person decides about a night, scored on something measured
    /// rather than chosen -- and pinned here because a map scored on one of
    /// its own axes would report that longer nights are longer.
    func testTheRecordedMapIsTheOneTheAppDraws() {
        let configuration = SleepMap.defaultConfiguration
        XCTAssertEqual(configuration.x, .bedtime)
        XCTAssertEqual(configuration.y, .duration)
        XCTAssertEqual(configuration.outcome, .hrv)
        XCTAssertNotEqual(configuration.outcome, configuration.x)
        XCTAssertNotEqual(configuration.outcome, configuration.y)
    }

    func testASeparatedMapIsRecordedAsObserved() throws {
        let map = try builtMap(gridNights())
        _ = try XCTUnwrap(map.best, "fixture scored no region")
        XCTAssertTrue(
            map.headlineIsSupported,
            "fixture must separate its regions, or this test is asserting on the other branch"
        )

        let revision = try XCTUnwrap(EvidenceLedger.revision(for: map))
        XCTAssertEqual(revision.status, .observed)
        XCTAssertEqual(revision.provenance, "SleepMap")
        XCTAssertEqual(revision.claimID, "sleepMap:duration:restingHeartRate:hrv")
    }

    /// The distinction `SleepMap.headlineIsSupported` exists to draw: the
    /// better nights cluster somewhere, and the regions are still too close
    /// to call one better. Recording both as `.observed` would erase it.
    func testAMapThatCannotSeparateItsRegionsIsRecordedAsInconclusive() throws {
        // Every cell the same, so no region can be shown to beat the next.
        let map = try builtMap(gridNights(standoutHRV: 52))
        _ = try XCTUnwrap(map.best, "fixture scored no region")
        XCTAssertFalse(
            map.headlineIsSupported,
            "fixture must fail to separate, or this test is asserting on the other branch"
        )
        XCTAssertEqual(EvidenceLedger.revision(for: map)?.status, .inconclusive)
    }

    /// `Revision.effect` is a signed *change* -- every consumer renders it
    /// with a leading + or -. A map reports a level, and "+62 ms" for a
    /// median of 62 ms would turn a measurement into a difference from
    /// nothing. The number is in the stored headline instead.
    func testAMapRecordsNoEffectBecauseItHasNoChangeToReport() throws {
        let map = try builtMap(gridNights())
        let revision = try XCTUnwrap(EvidenceLedger.revision(for: map))
        XCTAssertNil(revision.effect)
        XCTAssertNil(revision.effectUnit)
        XCTAssertNil(revision.uncertaintyLower)
        XCTAssertFalse(revision.headline.isEmpty)
    }

    // MARK: - Experiments

    private func outcome(
        tag: String = "alcohol",
        baseline: Double = 400,
        trial: Double = 440,
        higherIsBetter: Bool = true,
        baselineNights: Int = 14,
        trialNights: Int = 20,
        compliant: Int? = 18
    ) -> SleepExperimentStore.Outcome {
        SleepExperimentStore.Outcome(
            id: UUID(),
            tag: tag,
            hypothesis: "Skipping alcohol lets me sleep longer",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_000 + 20 * 86_400),
            metricLabel: "deep sleep",
            baselineMedian: baseline,
            trialMedian: trial,
            baselineNightCount: baselineNights,
            trialNightCount: trialNights,
            higherIsBetter: higherIsBetter,
            trialKnownNightCount: trialNights,
            direction: .avoid,
            trialCompliantNightCount: compliant
        )
    }

    func testAnAdherentExperimentThatWorkedIsSupported() {
        let revision = EvidenceLedger.revision(for: outcome())
        XCTAssertEqual(revision.status, .supported)
        XCTAssertEqual(revision.claimID, "experiment:alcohol")
        XCTAssertEqual(revision.provenance, "GuidedExperiment")
        XCTAssertEqual(revision.effect, 40)
        // `Outcome.metricLabel` is the metric's name, not its unit, and the
        // outcome record has never carried a unit. Claiming one would render
        // "+40 deep sleep".
        XCTAssertNil(revision.effectUnit)
        XCTAssertEqual(revision.sourceFeature, "deep sleep")
        XCTAssertEqual(revision.windowStart, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testAnAdherentExperimentThatWentTheWrongWayIsNotSupported() {
        XCTAssertEqual(
            EvidenceLedger.revision(for: outcome(trial: 350)).status, .notSupported
        )
    }

    /// Adherence is checked before the medians, and this is why. A trial the
    /// behaviour was never actually kept in cannot support or refute
    /// anything, however far apart the two periods landed.
    func testATrialNobodyKeptIsInconclusiveHoweverTheMediansFell() {
        for trial in [440.0, 350.0] {
            let revision = EvidenceLedger.revision(for: outcome(trial: trial, compliant: 8))
            XCTAssertEqual(revision.status, .inconclusive, "trial median \(trial)")
        }
    }

    /// An outcome recorded before adherence was tracked has no adherence to
    /// check, and a missing figure is not a passing one.
    func testAnOutcomeWithNoAdherenceFigureIsInconclusive() {
        XCTAssertEqual(EvidenceLedger.revision(for: outcome(compliant: nil)).status, .inconclusive)
    }

    /// The guard against the opposite mistake: calling a 0.5% drift "not
    /// supported" and writing that down as an answer.
    func testAnExperimentThatBarelyMovedAnythingIsInconclusive() {
        XCTAssertEqual(EvidenceLedger.revision(for: outcome(trial: 398)).status, .inconclusive)
    }

    /// 14 baseline nights against 18 compliant trial nights rests on 14.
    func testAnExperimentRestsOnItsThinnerSide() {
        XCTAssertEqual(EvidenceLedger.revision(for: outcome()).sampleSize, 14)
        XCTAssertEqual(
            EvidenceLedger.revision(for: outcome(baselineNights: 30, compliant: 9)).sampleSize, 9
        )
    }

    /// The headline is kept verbatim forever, so it has to carry the four
    /// things a reader would need a year later: what was tested, which way it
    /// moved, by how much, and how well the trial was actually kept.
    func testTheStoredHeadlineNamesTheBehaviourTheSizeAndTheAdherence() {
        let headline = EvidenceLedger.revision(for: outcome()).headline
        XCTAssertTrue(headline.contains("alcohol"), headline)
        XCTAssertTrue(headline.contains("deep sleep"), headline)
        XCTAssertTrue(headline.contains("+40"), headline)
        XCTAssertTrue(headline.contains("90%"), headline)
        XCTAssertFalse(headline.contains("Alcohol"), "mid-sentence label was not lower-cased: \(headline)")
    }

    // MARK: - The ledger still behaves

    /// The new statuses go through the same append-only rule as the old ones:
    /// a status move is always material, and an unchanged belief is not.
    func testANewStatusStillFollowsTheAppendOnlyRule() {
        let observed = EvidenceLedger.revision(for: changePoint(), at: Date(timeIntervalSince1970: 1))
        let same = EvidenceLedger.revision(for: changePoint(), at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(EvidenceLedger.recording(same, into: [observed]).count, 1)

        let moved = EvidenceLedger.revision(
            for: changePoint(after: 70), at: Date(timeIntervalSince1970: 3)
        )
        XCTAssertEqual(EvidenceLedger.recording(moved, into: [observed]).count, 2)
    }
}
