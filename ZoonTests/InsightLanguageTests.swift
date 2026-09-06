import XCTest

/// What the rule engine is allowed to claim.
///
/// Zoon's rules observe things co-occurring on a single night. Five strings in
/// `RuleBasedInsightEngine` and `WeeklyReport` went further than that and
/// asserted a cause, a mechanism, or a readiness verdict:
///
/// - "your body is fighting something off" (illness, from temperature + HRV)
/// - "deep sleep is the first thing to suffer"
/// - "Fragmentation like this usually traces to ..."
/// - "Your nervous system stayed in gear overnight -- typically ..."
/// - "You spent most of the week ready to train."
///
/// `JournalCorrelator` goes to considerable trouble over matched pairs and
/// bootstrap intervals precisely because a co-occurrence is not a cause. Copy
/// like the above throws that away in four words, on the screen most people
/// actually read.
///
/// This file exists so the strings cannot come back. The engine is compiled
/// into the test target specifically to make that assertable rather than
/// reviewable by eye.
final class InsightLanguageTests: XCTestCase {

    private let engine = RuleBasedInsightEngine()

    private func baseline(
        hrv: Double? = 55,
        deep: Double? = 120,
        duration: Double? = 450,
        efficiency: Double? = 92,
        minHR: Double? = 48,
        restingHR: Double? = 54,
        wristTempC: Double? = 34.0,
        bedtimeConsistencyMinutes: Double? = 25,
        sampleCount: Int = 14
    ) -> RollingBaseline {
        RollingBaseline(
            hrv7DayAvg: hrv,
            sleepDebtMinutes: 0,
            deep7DayAvg: deep,
            duration7DayAvg: duration,
            efficiency7DayAvg: efficiency,
            minHeartRate7DayAvg: minHR,
            restingHeartRate7DayAvg: restingHR,
            wristTempBaselineC: wristTempC,
            bedtimeConsistencyMinutes: bedtimeConsistencyMinutes,
            sampleCount: sampleCount
        )
    }

    /// Every user-visible string the engine produced.
    ///
    /// `generalContext` is in here, and has to be: the V4 split moved half of
    /// each rule's copy into that field, and a negative assertion that stops
    /// looking at a string it used to cover is an assertion that silently
    /// stopped working.
    private func text(of insight: SleepInsight) -> String {
        [
            insight.summary,
            insight.likelyCause ?? "",
            insight.generalContext ?? "",
            insight.actionableTip
        ].joined(separator: " ")
    }

    /// Just the parts that make a claim about the night.
    ///
    /// Deliberately excludes the tip, because the tip is where the
    /// non-diagnostic note is appended for physiological findings -- and that
    /// note reads "Zoon can't diagnose anything", which
    /// `DiagnosticLanguageGuard.bannedTerms` catches on the stem "diagnos".
    /// That match is correct for its real job of screening model output (see
    /// `DiagnosticLanguageGuardTests.testMatchesAsSubstringWithinALongerWord`),
    /// so the engine's own copy is checked in two parts rather than loosening
    /// the guard: diagnostic language against the claim, causal overclaiming
    /// against everything including the tip.
    private func claim(of insight: SleepInsight) -> String {
        [insight.summary, insight.likelyCause ?? "", insight.generalContext ?? ""]
            .joined(separator: " ")
    }

    private func insight(
        _ night: SleepNightFeatures,
        baseline: RollingBaseline? = nil
    ) -> SleepInsight {
        engine.generate(
            for: night,
            baseline: baseline ?? self.baseline(),
            goalMinutes: 480
        )
    }

    // MARK: - The five strings, by name

    /// Temperature up and HRV down used to be reported as the body "fighting
    /// something off" -- an illness claim, from two signals, on one night.
    func testTemperatureAndHRVDoNotImplyIllness() {
        let night = Fixture.night(avgHRV: 38, wristTempDeltaC: 0.9)
        let insight = insight(night)
        let all = text(of: insight).lowercased()

        XCTAssertFalse(all.contains("fighting something off"), all)
        XCTAssertFalse(all.contains("infection"), all)
        XCTAssertFalse(all.contains("illness"), all)
        // And it still says something useful about the two signals.
        XCTAssertTrue(all.contains("temperature"), all)
    }

    func testLateTrainingDoesNotAssertAMechanism() {
        let night = Fixture.night(avgHRV: 55, lastWorkoutHoursBeforeBed: 1.0)
        let all = text(of: insight(night, baseline: baseline(deep: 200))).lowercased()

        XCTAssertFalse(all.contains("first thing to suffer"), all)
        XCTAssertFalse(all.contains("adrenaline"), all)
    }

    func testFragmentationDoesNotAttributeACause() {
        let night = Fixture.night(
            timeAsleepMinutes: 360, timeInBedMinutes: 480,
            avgHRV: 55, wristTempDeltaC: 0.0, avgSpO2: 97, wakeCount: 7
        )
        let all = text(of: insight(night)).lowercased()

        XCTAssertFalse(all.contains("traces to"), all)
    }

    func testElevatedHeartRateDoesNotAssertNervousSystemState() {
        let night = Fixture.night(avgHRV: 38, minHeartRate: 60, wristTempDeltaC: 0.0)
        let all = text(of: insight(night)).lowercased()

        XCTAssertFalse(all.contains("stayed in gear"), all)
    }

    // MARK: - Two the first pass missed

    /// An irregular bedtime used to be told it "costs you deep sleep".
    ///
    /// The rule fires on bedtime spread alone -- it never reads the person's
    /// deep sleep at all -- so that sentence asserted a mechanism about
    /// someone from data containing no trace of it. The V9 spec names this
    /// exact claim ("irregularity causes architecture loss") as one not to
    /// make.
    func testIrregularBedtimeDoesNotClaimItCostsDeepSleep() {
        let swinging = baseline(bedtimeConsistencyMinutes: 95)
        let all = text(of: insight(Fixture.night(), baseline: swinging)).lowercased()

        // The rule has to have fired, or the assertions below pass for the
        // wrong reason.
        XCTAssertTrue(all.contains("bedtime has swung"), all)

        XCTAssertFalse(all.contains("costs you deep sleep"), all)
        XCTAssertFalse(all.contains("shifts your body clock around"), all)
    }

    /// Low deep sleep used to be explained by "a late bedtime or a disturbed
    /// first few hours" -- neither of which the rule checks. The physiology
    /// is real, so it stays; presenting it as the reason for last night does
    /// not.
    func testLowDeepSleepDoesNotBlameAnUncheckedBedtime() {
        let night = Fixture.night(avgHRV: 55, wristTempDeltaC: 0.0)
        let all = text(of: insight(night, baseline: baseline(deep: 220))).lowercased()

        // Same reason as above: assert the rule fired before asserting what
        // it does not say.
        XCTAssertTrue(all.contains("deep sleep came in"), all)
        XCTAssertFalse(all.contains("hits it hardest"), all)
    }

    // MARK: - Nothing anywhere in the matrix

    /// A sweep rather than one fixture per rule. Any rule that fires under
    /// any of these combinations has its whole output checked, so a phrase
    /// reintroduced in a rule this file never names is still caught.
    func testNoRuleOverclaimsCausationOrDiagnoses() {
        var checked = 0
        for hrv in [Double(30), 45, 55, 70] {
            for temp in [Double(0), 0.6, 1.2] {
                for spo2 in [Double(88), 93, 98] {
                    for wakes in [1, 6] {
                        for workout in [Double?.none, 1.0, 5.0] {
                            for asleep in [Double(300), 450] {
                                let night = Fixture.night(
                                    timeAsleepMinutes: asleep,
                                    avgHRV: hrv,
                                    minHeartRate: 58,
                                    wristTempDeltaC: temp,
                                    avgSpO2: spo2,
                                    wakeCount: wakes,
                                    lastWorkoutHoursBeforeBed: workout
                                )
                                let generated = insight(night)
                                let all = text(of: generated)
                                XCTAssertFalse(
                                    DiagnosticLanguageGuard.overclaimsCausation(all),
                                    "causal overclaim: \(all)"
                                )
                                XCTAssertFalse(
                                    DiagnosticLanguageGuard.containsBannedLanguage(claim(of: generated)),
                                    "diagnostic language: \(claim(of: generated))"
                                )
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 200, "the sweep should actually be broad")
    }

    // MARK: - Two tiers, not one paragraph (V10 item 11)

    /// The split the whole item is about. Every rule here had a measurement
    /// and a general finding concatenated into one sentence in one voice, so
    /// the general half read as the reason for last night.
    func testTheMeasurementAndTheGeneralFindingAreSeparateFields() throws {
        let night = Fixture.night(avgHRV: 55, lastWorkoutHoursBeforeBed: 1.0)
        let insight = insight(night, baseline: baseline(deep: 200))

        let measured = try XCTUnwrap(insight.likelyCause)
        let general = try XCTUnwrap(insight.generalContext)

        // The measurement names this person's numbers.
        XCTAssertTrue(measured.contains("Deep sleep"), measured)
        XCTAssertTrue(measured.contains("your usual"), measured)
        // The general finding does not quote them back.
        XCTAssertFalse(general.contains("your usual"), general)
        XCTAssertFalse(general.contains("%"), general)
    }

    /// The observed tier is what was measured. If a general-population claim
    /// leaks back into it, the separation has been undone without anything
    /// failing to compile.
    ///
    /// The phrases below are the ones the V4 split moved out of
    /// `likelyCause`, checked by hand against every rule in the engine, so
    /// this fails the moment one is written back into the measurement.
    func testGeneralPopulationClaimsStayOutOfTheMeasuredTier() {
        let leaked = [
            "travel together",
            "usually check",
            "worth checking first",
            "commonly associated",
            "is associated with",
            "sleep research associates",
            "builds quietly",
            "most deep sleep happens",
            "alcohol and some medications",
            "often occur near each other",
            "can be thrown off"
        ]

        var checked = 0
        for hrv in [38.0, 55.0] {
            for temp in [0.0, 0.9] {
                for wakes in [2, 7] {
                    for workout in [nil, 1.0] as [Double?] {
                        for spo2 in [88.0, 97.0] {
                            let night = Fixture.night(
                                timeAsleepMinutes: 360, timeInBedMinutes: 480,
                                avgHRV: hrv, wristTempDeltaC: temp, avgSpO2: spo2,
                                wakeCount: wakes, lastWorkoutHoursBeforeBed: workout
                            )
                            guard let measured = insight(night).likelyCause else { continue }
                            let lowered = measured.lowercased()
                            for phrase in leaked {
                                XCTAssertFalse(
                                    lowered.contains(phrase),
                                    "general-population phrase \"\(phrase)\" is in the measured tier: \(measured)"
                                )
                            }
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 20, "the sweep should actually reach the rules")
    }

    /// A rule that is pure arithmetic against the person's own goal has no
    /// general finding to add, and must not have one invented for symmetry.
    func testARuleWithNothingGeneralToSayAddsNothing() {
        // Short of goal, everything else unremarkable: `shortSleepRule` wins.
        let night = Fixture.night(
            timeAsleepMinutes: 360, timeInBedMinutes: 380,
            avgHRV: 55, wristTempDeltaC: 0.0, avgSpO2: 97, wakeCount: 1
        )
        let insight = insight(night)
        XCTAssertTrue(insight.likelyCause?.contains("short of your") == true, insight.likelyCause ?? "")
        XCTAssertNil(insight.generalContext)
    }

    /// Every rule still produces something. A guard that passes because the
    /// engine went silent would be worthless.
    func testTheEngineStillSaysSomething() {
        let night = Fixture.night(avgHRV: 38, wristTempDeltaC: 0.9)
        let insight = insight(night)
        XCTAssertFalse(insight.summary.isEmpty)
        XCTAssertFalse(insight.actionableTip.isEmpty)
        XCTAssertNotNil(insight.likelyCause)
    }

    /// Findings built on temperature, SpO2 or respiratory rate carry the
    /// non-diagnostic reminder inline rather than only in Settings.
    func testPhysiologicalFindingsCarryTheNonDiagnosticNote() {
        let night = Fixture.night(avgHRV: 38, wristTempDeltaC: 0.9)
        XCTAssertTrue(
            insight(night).actionableTip.contains("can't diagnose"),
            insight(night).actionableTip
        )
    }

    /// The reason `claim(of:)` exists, stated as a test so the split in the
    /// sweep above reads as deliberate rather than as an oversight.
    ///
    /// Zoon's own non-diagnostic disclaimer contains the word "diagnose",
    /// which the guard matches on the stem "diagnos". Over-matching is the
    /// right call for screening model output -- but it means the guard cannot
    /// be pointed at Zoon's own disclaimer and expected to pass.
    func testTheGuardFlagsZoonsOwnNonDiagnosticNote() {
        let note = "Zoon can't diagnose anything \u{2014} this is an observation, not a finding."
        XCTAssertTrue(
            DiagnosticLanguageGuard.containsBannedLanguage(note),
            "if this ever stops matching, the sweep can check the tip too"
        )
        XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(note))
    }

    // MARK: - Weekly report

    func testWeeklyRecoveryHighlightDoesNotPrescribeTraining() {
        let nights = Fixture.consecutiveNights(7)
        for recovery in [80, 40] {
            let recoveries = Dictionary(uniqueKeysWithValues: nights.map { ($0.date, recovery) })
            let report = WeeklyReport.build(
                nights: nights,
                recoveries: recoveries,
                previousNights: [],
                previousRecoveries: [:],
                goalMinutes: 480,
                consistencyMinutes: nil
            )
            let all = report.highlights.map { "\($0.title) \($0.detail)" }
                .joined(separator: " ").lowercased()
            XCTAssertFalse(all.contains("ready to train"), all)
            XCTAssertFalse(all.contains("sleep is the lever"), all)
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(all), all)

            // When the recovery highlight is present it reads descriptively.
            // Guarded rather than required, because `build` only appends it
            // while fewer than four highlights exist.
            if let detail = report.highlights
                .first(where: { $0.title.contains("Average recovery") })?.detail {
                XCTAssertTrue(detail.contains("Recovery sat"), detail)
            }
        }
    }
}
