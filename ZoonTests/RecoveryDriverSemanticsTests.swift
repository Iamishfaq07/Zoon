import XCTest

/// One scale under four signals that are not on one scale.
///
/// `RecoveryScore` normalizes HRV as `0.5 + deviation/0.5`, resting heart
/// rate as `0.5 - deviation/0.24`, respiration as `1 - abs(delta)/1.5` and
/// sleep as `performance/100`. A person whose HRV and resting heart rate were
/// exactly normal for them therefore sat at 0.50 on both and read "Fair",
/// while their equally normal respiration sat at 1.00 and read "Optimal".
final class RecoveryDriverSemanticsTests: XCTestCase {

    private func component(
        _ label: String,
        normalized: Double,
        deviationPercent: Double? = nil,
        detail: String = "—",
        available: Bool = true
    ) -> RecoveryScore.Component {
        RecoveryScore.Component(
            label: label,
            detail: detail,
            normalized: normalized,
            weight: 0.25,
            effectiveWeight: 0.25,
            isAvailable: available,
            deviationPercent: deviationPercent
        )
    }

    private func phrase(_ component: RecoveryScore.Component) -> String {
        RecoveryDriverSemantics.reading(for: component).phrase
    }

    // MARK: - The word that started it

    /// The brief's own example, and the assertion the old code failed.
    ///
    /// 82% of target is roughly eighty-six minutes short of an eight-hour
    /// target. The old scale called that "Optimal" because 0.82 cleared its
    /// 0.78 cutoff; it is "Below target", which is what the number says.
    func testEightyTwoPercentOfSleepNeedIsNotOptimal() {
        let sleep = component("Sleep", normalized: 0.82, detail: "82% of target")
        XCTAssertNotEqual(phrase(sleep), "Optimal")
        XCTAssertEqual(phrase(sleep), "Below target")
        XCTAssertTrue(RecoveryDriverSemantics.reading(for: sleep).standing.deservesEmphasis)
    }

    /// And the band between: short of target, but not by enough to lead with.
    func testANightJustUnderTargetReadsAsNear() {
        XCTAssertEqual(phrase(component("Sleep", normalized: 0.90, detail: "90% of target")), "Near target")
    }

    /// No driver, at any value, says "Optimal". A single overnight reading
    /// from a consumer wearable does not establish that anything is optimal.
    func testNoDriverEverSaysOptimal() {
        for driver in RecoveryDriverSemantics.Driver.allCases {
            for normalized in stride(from: 0.0, through: 1.0, by: 0.05) {
                let reading = phrase(
                    component(driver.rawValue, normalized: normalized, deviationPercent: 1)
                )
                XCTAssertNotEqual(reading, "Optimal", "\(driver.rawValue) at \(normalized)")
                XCTAssertFalse(reading.lowercased().contains("optimal"))
            }
        }
    }

    // MARK: - At their own baseline

    /// The heart of it: HRV and resting heart rate normalize to 0.50 at
    /// baseline, and respiration to 1.00. All three are the same statement
    /// about the body — nothing unusual — and must now read that way rather
    /// than as "Fair", "Fair" and "Optimal".
    func testEverySignalAtItsOwnBaselineReadsAsTypical() {
        let atBaseline = [
            component("HRV", normalized: 0.5, deviationPercent: 0),
            component("Resting HR", normalized: 0.5, deviationPercent: 0),
            component("Respiratory", normalized: 1.0, deviationPercent: 0)
        ]
        for signal in atBaseline {
            XCTAssertEqual(
                RecoveryDriverSemantics.reading(for: signal).standing, .typical,
                "\(signal.label) at baseline did not read as typical"
            )
        }
        XCTAssertEqual(phrase(atBaseline[0]), "Near baseline")
        XCTAssertEqual(phrase(atBaseline[1]), "Near baseline")
        XCTAssertEqual(phrase(atBaseline[2]), "Within usual range")
    }

    /// Stated as the regression it was: two signals that are equally
    /// unremarkable must not get differently-graded words.
    func testBaselineHRVAndBaselineRespirationDoNotDisagree() {
        let hrv = component("HRV", normalized: 0.5, deviationPercent: 0)
        let respiratory = component("Respiratory", normalized: 1.0, deviationPercent: 0)
        XCTAssertEqual(
            RecoveryDriverSemantics.reading(for: hrv).standing,
            RecoveryDriverSemantics.reading(for: respiratory).standing
        )
    }

    // MARK: - HRV

    func testHRVBelowBaselineSaysSo() {
        XCTAssertEqual(phrase(component("HRV", normalized: 0.2, deviationPercent: -15)), "Below your baseline")
    }

    func testHRVAboveBaselineSaysSo() {
        XCTAssertEqual(phrase(component("HRV", normalized: 0.8, deviationPercent: 15)), "Above your baseline")
    }

    /// Only a drop is worth colouring. A raised HRV is real and is not
    /// something to act on.
    func testOnlyHRVBelowBaselineIsEmphasised() {
        XCTAssertTrue(RecoveryDriverSemantics.reading(for: component("HRV", normalized: 0.2)).standing.deservesEmphasis)
        XCTAssertFalse(RecoveryDriverSemantics.reading(for: component("HRV", normalized: 0.8)).standing.deservesEmphasis)
        XCTAssertFalse(RecoveryDriverSemantics.reading(for: component("HRV", normalized: 0.5)).standing.deservesEmphasis)
    }

    // MARK: - Resting heart rate runs the other way

    /// The scale is inverted, so a *low* normalized value is a *high* rate.
    /// Getting this backwards would tell somebody their heart rate was low on
    /// the morning it was high.
    func testRestingHeartRateDirectionIsNotInverted() {
        let highRate = component("Resting HR", normalized: 0.2, deviationPercent: 8)
        let lowRate = component("Resting HR", normalized: 0.8, deviationPercent: -8)
        XCTAssertEqual(phrase(highRate), "Above your baseline")
        XCTAssertEqual(phrase(lowRate), "Below your baseline")
        XCTAssertTrue(RecoveryDriverSemantics.reading(for: highRate).standing.deservesEmphasis)
        XCTAssertFalse(RecoveryDriverSemantics.reading(for: lowRate).standing.deservesEmphasis)
    }

    // MARK: - Respiration

    func testRaisedRespirationSaysAboveUsualRange() {
        XCTAssertEqual(
            phrase(component("Respiratory", normalized: 0.2, deviationPercent: 9)),
            "Above usual range"
        )
    }

    func testLoweredRespirationSaysBelowUsualRange() {
        XCTAssertEqual(
            phrase(component("Respiratory", normalized: 0.2, deviationPercent: -9)),
            "Below usual range"
        )
    }

    /// Half a breath per minute from baseline is `1 - 0.5/1.5`, and is still
    /// within the range this signal wanders in on an ordinary night.
    func testHalfABreathFromBaselineIsStillUsual() {
        XCTAssertEqual(
            phrase(component("Respiratory", normalized: 1 - 0.5 / 1.5, deviationPercent: 3)),
            "Within usual range"
        )
    }

    // MARK: - Sleep

    func testSleepAtTargetSaysTargetMet() {
        XCTAssertEqual(phrase(component("Sleep", normalized: 1.0, detail: "100% of target")), "Target met")
    }

    /// A planning estimate does not deserve to be missed by four minutes.
    func testSleepJustShortOfTargetStillCountsAsMet() {
        XCTAssertEqual(phrase(component("Sleep", normalized: 0.97, detail: "97% of target")), "Target met")
    }

    func testAClearlyShortNightSaysBelowTarget() {
        let short = component("Sleep", normalized: 0.6, detail: "60% of target")
        XCTAssertEqual(phrase(short), "Below target")
        XCTAssertTrue(RecoveryDriverSemantics.reading(for: short).standing.deservesEmphasis)
    }

    // MARK: - Missing

    func testAnUnmeasuredSignalSaysSoRatherThanScoring() {
        let missing = component("HRV", normalized: 0, available: false)
        XCTAssertEqual(phrase(missing), "Not measured")
        XCTAssertEqual(RecoveryDriverSemantics.reading(for: missing).standing, .unmeasured)
        XCTAssertFalse(RecoveryDriverSemantics.reading(for: missing).standing.deservesEmphasis)
    }

    /// A normalized 0 on an unavailable signal is a placeholder, not a
    /// reading, and must never be worded as one.
    func testAnUnmeasuredSignalIsNotReadAsBelowBaseline() {
        XCTAssertNotEqual(phrase(component("HRV", normalized: 0, available: false)), "Below your baseline")
    }

    // MARK: - Colour restraint

    /// The brief's instruction: not four simultaneous verdict systems. At
    /// most the signals genuinely away from baseline take colour.
    func testAnOrdinaryMorningColoursNothing() {
        let ordinary = [
            component("HRV", normalized: 0.5, deviationPercent: 0),
            component("Resting HR", normalized: 0.5, deviationPercent: 0),
            component("Sleep", normalized: 0.98, detail: "98% of target"),
            component("Respiratory", normalized: 1.0, deviationPercent: 0)
        ]
        XCTAssertTrue(
            ordinary.allSatisfy { !RecoveryDriverSemantics.reading(for: $0).standing.deservesEmphasis }
        )
    }

    // MARK: - VoiceOver

    /// The brief's example, verbatim in shape: the relationship, spoken, with
    /// the unit spelled out.
    func testVoiceOverSaysTheRelationshipRatherThanAGrade() {
        let hrv = component("HRV", normalized: 0.2, deviationPercent: -15, detail: "50 ms")
        let label = RecoveryDriverSemantics.accessibilityLabel(for: hrv)
        XCTAssertEqual(label, "HRV, 50 milliseconds, below your baseline")
        XCTAssertFalse(label.contains(" ms"))
        XCTAssertFalse(label.lowercased().hasSuffix("low"))
    }

    func testSpokenUnitsAreSpelledOut() {
        XCTAssertEqual(RecoveryDriverSemantics.spokenReading("62 bpm"), "62 beats per minute")
        XCTAssertEqual(RecoveryDriverSemantics.spokenReading("15.1 br/min"), "15.1 breaths per minute")
        XCTAssertEqual(RecoveryDriverSemantics.spokenReading("50 ms"), "50 milliseconds")
    }

    /// "82% of target" has no unit abbreviation to expand and must come back
    /// untouched rather than mangled.
    func testAReadingWithNoUnitAbbreviationIsUnchanged() {
        XCTAssertEqual(RecoveryDriverSemantics.spokenReading("82% of target"), "82% of target")
    }

    func testAnUnmeasuredSignalIsSpokenAsNotMeasured() {
        let missing = component("Resting HR", normalized: 0, available: false)
        XCTAssertEqual(
            RecoveryDriverSemantics.accessibilityLabel(for: missing),
            "Resting HR, not measured"
        )
    }
}
