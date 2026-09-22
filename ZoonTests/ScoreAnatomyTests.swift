import XCTest

/// What tapping a Recovery driver shows, and the weighting it reports.
final class ScoreAnatomyTests: XCTestCase {

    private func component(
        _ label: String,
        detail: String = "50 ms",
        normalized: Double = 0.4,
        weight: Double = 0.35,
        effectiveWeight: Double = 0.45,
        isAvailable: Bool = true,
        deviationPercent: Double? = nil
    ) -> RecoveryScore.Component {
        RecoveryScore.Component(
            label: label,
            detail: detail,
            normalized: normalized,
            weight: weight,
            effectiveWeight: effectiveWeight,
            isAvailable: isAvailable,
            deviationPercent: deviationPercent
        )
    }

    /// The share reported is the one the component actually carried, not the
    /// one the scoring table nominally assigns.
    ///
    /// These differ exactly when something was missing and its weight was
    /// redistributed -- which is when the reader most needs the truth. The
    /// spec asks for "today's Recovery weighting", and today is the night
    /// where respiratory rate never arrived.
    func testTheWeightingIsTodaysNotTheTableS() {
        let detail = ScoreAnatomy.detail(
            for: component("HRV", weight: 0.35, effectiveWeight: 0.45)
        )
        XCTAssertTrue(detail.contribution.contains("45%"), detail.contribution)
        XCTAssertFalse(detail.contribution.contains("35%"), detail.contribution)
    }

    /// A component that carried nothing says so. "0% of today's Recovery
    /// weighting" reads as a measured contribution of zero, which is the same
    /// missing-is-not-zero failure the watch's recovery dial had, written as a
    /// sentence instead of a number.
    func testAMissingSignalIsNotReportedAsZeroPercent() {
        let missing = ScoreAnatomy.detail(
            for: component("Respiratory", effectiveWeight: 0, isAvailable: false)
        )
        XCTAssertFalse(missing.contribution.contains("0%"), missing.contribution)
        XCTAssertEqual(missing.contribution, "Not counted in today's score")
        XCTAssertEqual(missing.value, "—", "a missing reading must not print a number")
        XCTAssertFalse(missing.isAvailable)
    }

    /// Available but weightless is the same statement: it did not count.
    func testAnAvailableSignalCarryingNoWeightAlsoSaysSo() {
        let detail = ScoreAnatomy.detail(for: component("Sleep", effectiveWeight: 0))
        XCTAssertEqual(detail.contribution, "Not counted in today's score")
    }

    /// The comparison is not re-derived here. Two phrasings of one comparison
    /// is how a screen starts contradicting itself.
    func testTheComparisonComesFromTheEstablishedWording() {
        let c = component("HRV", normalized: 0.2)
        XCTAssertEqual(
            ScoreAnatomy.detail(for: c).comparison,
            RecoveryDriverSemantics.reading(for: c).phrase
        )
    }

    func testPercentRounds() {
        XCTAssertEqual(ScoreAnatomy.percent(0.452), 45)
        XCTAssertEqual(ScoreAnatomy.percent(0.455), 46)
        XCTAssertEqual(ScoreAnatomy.percent(1.5), 100, "clamped rather than reported as 150%")
        XCTAssertEqual(ScoreAnatomy.percent(-1), 0)
        XCTAssertEqual(ScoreAnatomy.percent(.nan), 0)
    }

    /// The ring's centre is capped at just over half its width so text
    /// cannot reach the radar vertices level with it. The long form is twice
    /// what fits, so a short one exists and still refuses to print 0%.
    func testTheCompactFormFitsAndStaysHonest() {
        let carried = ScoreAnatomy.compactContribution(for: component("HRV", effectiveWeight: 0.45))
        XCTAssertEqual(carried, "45% of the score")
        XCTAssertLessThan(
            carried.count,
            ScoreAnatomy.contribution(for: component("HRV", effectiveWeight: 0.45)).count
        )

        let missing = ScoreAnatomy.compactContribution(
            for: component("Respiratory", effectiveWeight: 0, isAvailable: false)
        )
        XCTAssertFalse(missing.contains("0%"), missing)
        XCTAssertEqual(missing, "Carries no weight today")
    }

    /// The view computed this inline as `Int((effectiveWeight * 100).rounded())`,
    /// which traps on a non-finite Double rather than printing anything. A
    /// scoring bug upstream should produce a wrong percentage, not a crash on
    /// the app's main screen.
    func testANonFiniteWeightDoesNotTrap() {
        for bad in [Double.nan, .infinity, -.infinity] {
            let c = component("HRV", effectiveWeight: bad)
            XCTAssertEqual(ScoreAnatomy.percent(bad), 0)
            XCTAssertEqual(ScoreAnatomy.compactContribution(for: c), "Carries no weight today")
        }
    }

    /// VoiceOver gets one sentence, not four fragments to assemble.
    func testTheSpokenFormIsOneSentence() {
        let spoken = ScoreAnatomy.accessibilityLabel(for: component("HRV", detail: "50 ms"))
        XCTAssertTrue(spoken.contains("milliseconds"), "units were left as an abbreviation: \(spoken)")
        XCTAssertTrue(spoken.contains("45%"), spoken)
    }

    /// A missing signal is spoken without a value, rather than reading an
    /// em dash aloud.
    func testAMissingSignalIsSpokenWithoutAValue() {
        let spoken = ScoreAnatomy.accessibilityLabel(
            for: component("Respiratory", effectiveWeight: 0, isAvailable: false)
        )
        XCTAssertFalse(spoken.contains("—"), spoken)
        XCTAssertTrue(spoken.contains("Not counted"), spoken)
    }

    /// The order the radar draws is the order these come back in, or the
    /// centre would describe a different signal from the one that was tapped.
    func testOrderIsPreserved() {
        let components = [component("HRV"), component("Resting HR"), component("Sleep")]
        XCTAssertEqual(
            ScoreAnatomy.details(for: components).map(\.label),
            ["HRV", "Resting HR", "Sleep"]
        )
    }
}
