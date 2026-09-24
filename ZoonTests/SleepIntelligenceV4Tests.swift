import XCTest

/// Sleep Intelligence v4: what changed from v3, pinned.
///
/// - Stage Pattern compares Deep/REM *composition*, so a night's length
///   cannot move it (v3 compared minutes and double-counted Duration).
/// - Stage Pattern runs only on stages `StageTrust` accepts, against a
///   baseline from the same kind of source.
/// - Continuity does not treat an inferred time in bed as a measured
///   efficiency.
/// - A severe shortfall caps the headline, transparently.
final class SleepIntelligenceV4Tests: XCTestCase {

    // MARK: - Fixtures

    /// Thirty nights with a little night-to-night spread in stage share,
    /// written by `source`.
    private func history(
        source: SourcePriority? = .appleWatch,
        asleep: Double = 450,
        count: Int = 30
    ) -> [SleepNightFeatures] {
        (0..<count).map { index in
            let wobble = Double((index * 7) % 5) - 2
            return Fixture.night(
                daysAgo: index + 1,
                timeAsleepMinutes: asleep,
                deepMinutes: asleep * (0.18 + 0.01 * wobble),
                remMinutes: asleep * (0.22 - 0.01 * wobble),
                stageSourcePriority: source
            )
        }
    }

    private func night(
        asleep: Double,
        deepShare: Double = 0.18,
        remShare: Double = 0.22,
        source: SourcePriority? = .appleWatch,
        timeInBed: Double? = nil,
        awake: Double? = nil,
        wakeCount: Int = 2,
        timeInBedIsEstimated: Bool = false
    ) -> SleepNightFeatures {
        Fixture.night(
            daysAgo: 0,
            timeAsleepMinutes: asleep,
            timeInBedMinutes: timeInBed ?? asleep + 30,
            wakeCount: wakeCount,
            deepMinutes: asleep * deepShare,
            remMinutes: asleep * remShare,
            timeInBedIsEstimated: timeInBedIsEstimated,
            awakeMinutes: awake,
            stageSourcePriority: source
        )
    }

    private func score(
        _ night: SleepNightFeatures,
        history: [SleepNightFeatures]? = nil,
        need: Double = 450,
        regularity: Double? = SleepIntelligenceScore.typicalRegularityIndex
    ) -> SleepIntelligenceScore {
        SleepIntelligenceScore.compute(.init(
            night: night,
            history: history ?? self.history(),
            sleepNeedMinutes: need,
            regularityIndex: regularity,
            habitualMidpointHours: nil
        ))
    }

    private func component(_ label: String, _ score: SleepIntelligenceScore) -> SleepIntelligenceScore.Component? {
        score.components.first { $0.label == label }
    }

    // MARK: - Composition, not duration

    /// The audit's own example: the same 18% Deep / 22% REM at 450 and at
    /// 360 minutes. v3 scored the short night as an unusual stage pattern.
    func testEqualStagePercentagesAtDifferentDurationsDoNotDiverge() throws {
        let long = try XCTUnwrap(component("Stage Pattern", score(night(asleep: 450))))
        let short = try XCTUnwrap(component("Stage Pattern", score(night(asleep: 360))))
        XCTAssertEqual(long.normalized, short.normalized, accuracy: 0.001)
        XCTAssertNotEqual(short.role, .limiting)
    }

    func testAnUnusualCompositionStillRegisters() throws {
        let usual = try XCTUnwrap(component("Stage Pattern", score(night(asleep: 450))))
        let unusual = try XCTUnwrap(component("Stage Pattern", score(night(asleep: 450, deepShare: 0.06, remShare: 0.34))))
        XCTAssertLessThan(unusual.normalized, usual.normalized - 0.1)
    }

    func testTheDetailStatesCompositionAndTheUsualRange() throws {
        let detail = try XCTUnwrap(component("Stage Pattern", score(night(asleep: 450)))).detail
        XCTAssertTrue(detail.contains("Deep 18%"), detail)
        XCTAssertTrue(detail.contains("usually"), detail)
        XCTAssertTrue(detail.contains("REM 22%"), detail)
    }

    // MARK: - StageTrust

    func testAppleWatchStagesAreScored() {
        XCTAssertNotNil(component("Stage Pattern", score(night(asleep: 450, source: .appleWatch))))
    }

    func testRecognisedWearableStagesAreScoredAgainstWearableHistory() {
        let wearable = score(
            night(asleep: 450, source: .thirdPartyWearable),
            history: history(source: .thirdPartyWearable)
        )
        XCTAssertNotNil(component("Stage Pattern", wearable))
    }

    func testInferredOrManualStagesDoNotAlterTheScore() {
        let inferred = night(asleep: 450, deepShare: 0.05, remShare: 0.40, source: .phoneOrManual)
        let result = score(inferred, history: history(source: .phoneOrManual))
        XCTAssertNil(component("Stage Pattern", result))

        // Same night with no stages at all: identical headline.
        let unstaged = Fixture.night(daysAgo: 0, timeAsleepMinutes: 450, timeInBedMinutes: 480, staged: false)
        XCTAssertEqual(result.percent, score(unstaged, history: history(source: .phoneOrManual)).percent)
    }

    func testUnattributedPreMigrationStagesAreExcluded() {
        XCTAssertNil(component("Stage Pattern", score(night(asleep: 450, source: nil), history: history(source: nil))))
    }

    func testLowTrustHistoryIsNotABaseline() {
        // A trusted night, but every earlier night was inferred.
        let result = score(night(asleep: 450, source: .appleWatch), history: history(source: .phoneOrManual))
        XCTAssertNil(component("Stage Pattern", result))
    }

    /// A change of device is not a change in sleep. A wearable night against
    /// thirty Apple Watch nights has no same-source baseline, so it is not
    /// scored as an unusual pattern.
    func testASourceChangeDoesNotCreateAnUnusualStagePattern() {
        let switched = score(
            night(asleep: 450, deepShare: 0.10, remShare: 0.30, source: .thirdPartyWearable),
            history: history(source: .appleWatch)
        )
        XCTAssertNil(component("Stage Pattern", switched))
    }

    func testTooLittleTrustedHistoryOmitsTheComponent() {
        let short = history(count: SleepIntelligenceScore.minimumStageBaselineNights - 1)
        XCTAssertNil(component("Stage Pattern", score(night(asleep: 450), history: short)))
    }

    // MARK: - Invariants

    func testMoreSleepTowardTheTargetNeverLowersDuration() throws {
        var previous = -1.0
        for asleep in stride(from: 210.0, through: 450.0, by: 10) {
            let duration = try XCTUnwrap(component("Duration", score(night(asleep: asleep))))
            XCTAssertGreaterThanOrEqual(duration.normalized, previous, "at \(asleep) minutes")
            previous = duration.normalized
        }
    }

    func testMoreWakeAfterOnsetNeverImprovesContinuity() throws {
        var previous = 2.0
        for awake in stride(from: 0.0, through: 120.0, by: 10) {
            let c = try XCTUnwrap(component("Continuity", score(night(asleep: 420, timeInBed: 420 + awake, awake: awake))))
            XCTAssertLessThanOrEqual(c.normalized, previous, "at \(awake) minutes awake")
            previous = c.normalized
        }
    }

    func testMoreAwakeningsNeverImproveContinuity() throws {
        var previous = 2.0
        for wakes in 0...12 {
            let c = try XCTUnwrap(component("Continuity", score(night(asleep: 420, wakeCount: wakes))))
            XCTAssertLessThanOrEqual(c.normalized, previous, "at \(wakes) awakenings")
            previous = c.normalized
        }
    }

    func testAMissingStagePatternCannotRaiseConfidenceOrCompleteness() {
        let full = score(night(asleep: 450))
        let noStages = score(Fixture.night(daysAgo: 0, timeAsleepMinutes: 450, timeInBedMinutes: 480, staged: false))
        XCTAssertLessThan(noStages.dataCompletenessPercent, full.dataCompletenessPercent)
        XCTAssertLessThanOrEqual(noStages.confidence, full.confidence)
        XCTAssertTrue(noStages.missingComponentLabels.contains("Stage Pattern"))
    }

    // MARK: - Severe shortfall

    /// Every other component as good as it gets: continuous, regular, the
    /// usual stage mix. Then shortfall alone decides how high the headline
    /// may go. The printed table is the audit's "inspect current maximum
    /// scores" request, answered in the test log.
    func testASevereShortfallCannotBeLabelledBetterThanItsCeiling() {
        let need = 480.0
        func best(short: Double) -> SleepIntelligenceScore {
            let asleep = need - short
            return score(
                night(asleep: asleep, timeInBed: asleep, awake: 0, wakeCount: 0),
                history: history(asleep: need),
                need: need,
                regularity: 100
            )
        }
        func rank(_ band: SleepIntelligenceScore.Band) -> Int {
            [.poor, .fair, .good, .excellent].firstIndex(of: band)!
        }

        for short in [30.0, 60, 90, 120, 180, 240] {
            let s = best(short: short)
            print("SI-v4 shortfall \(Int(short))m: \(s.percent) \(s.band.label), uncapped \(s.durationCap?.uncappedPercent ?? s.percent)")
            switch short {
            case 180...: XCTAssertEqual(s.band, .poor, "\(short)m short")
            case 120...: XCTAssertLessThanOrEqual(rank(s.band), rank(.fair), "\(short)m short")
            case 60...: XCTAssertLessThanOrEqual(rank(s.band), rank(.good), "\(short)m short")
            default: XCTAssertNil(s.durationCap, "30 minutes short is not severe")
            }
            if let cap = s.durationCap {
                XCTAssertEqual(s.percent, cap.ceiling)
                XCTAssertGreaterThan(cap.uncappedPercent, cap.ceiling)
                XCTAssertTrue(cap.explanation.contains("\(Int(short))m short"), cap.explanation)
            }
        }
    }

    func testTheCeilingNeverRaisesAScore() {
        let weak = score(night(asleep: 300, timeInBed: 420, awake: 90, wakeCount: 10), regularity: 20)
        XCTAssertNil(weak.durationCap, "an already-low score is not capped upward")
    }

    // MARK: - Estimated time in bed

    /// Asleep 425 of an inferred 500-minute window: an "efficiency" of 85%
    /// that nothing measured. With no wake after onset and no awakenings the
    /// estimated window scores continuity on what was measured, and does not
    /// call the ratio an efficiency.
    func testAnEstimatedWindowIsNotScoredAsMeasuredEfficiency() throws {
        let estimated = try XCTUnwrap(component("Continuity", score(
            night(asleep: 425, timeInBed: 500, awake: 0, wakeCount: 0, timeInBedIsEstimated: true)
        )))
        let measured = try XCTUnwrap(component("Continuity", score(
            night(asleep: 425, timeInBed: 500, awake: 0, wakeCount: 0, timeInBedIsEstimated: false)
        )))
        XCTAssertEqual(estimated.normalized, 1.0, accuracy: 0.001)
        XCTAssertLessThan(measured.normalized, estimated.normalized)
        XCTAssertFalse(estimated.detail.contains("efficient"), estimated.detail)
        XCTAssertTrue(estimated.detail.contains("estimated"), estimated.detail)
        XCTAssertTrue(measured.detail.contains("efficient"), measured.detail)
    }

    func testAnOrdinaryEstimatedNightIsTypical() {
        XCTAssertEqual(
            SleepIntelligenceScore.estimatedWindowContinuityNeutral,
            SleepIntelligenceScore.continuityNeutral,
            accuracy: 0.1,
            "the two continuity neutrals describe the same ordinary night"
        )
    }

    // MARK: - Version and serialisation

    func testVersionFourAndTheCapRoundTrip() throws {
        let capped = score(night(asleep: 330, timeInBed: 330, awake: 0, wakeCount: 0), history: history(asleep: 480), need: 480, regularity: 100)
        XCTAssertEqual(capped.scoringVersion, 4)
        let data = try JSONEncoder().encode(capped)
        let decoded = try JSONDecoder().decode(SleepIntelligenceScore.self, from: data)
        XCTAssertEqual(decoded, capped)
        XCTAssertEqual(decoded.durationCap, capped.durationCap)
    }

    /// A v3 score stored before the cap existed still decodes, as v3, with
    /// no cap -- it is not reinterpreted as v4.
    func testAVersionThreePayloadStillDecodesAsVersionThree() throws {
        let v4 = score(night(asleep: 450))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(v4)) as? [String: Any])
        object.removeValue(forKey: "durationCap")
        object["scoringVersion"] = 3
        let decoded = try JSONDecoder().decode(
            SleepIntelligenceScore.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.scoringVersion, 3)
        XCTAssertNil(decoded.durationCap)
    }
}
