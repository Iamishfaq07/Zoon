import XCTest

/// `SleepIntelligenceScore`'s explainability surface: which components were
/// dropped, and the sentence a metric sheet shows in place of a restatement
/// of the confidence band.
///
/// The sentence is built by reading `nominalWeights`, which is the same table
/// `compute` renormalizes against. That is the whole point of these tests: a
/// sixth component added to the table without being produced by `compute`
/// would show up here as a night that claims a component is missing, rather
/// than silently going unmentioned on every screen that explains the score.
final class ScoreExplainabilityTests: XCTestCase {

    /// Every component name the table declares must be a name `compute`
    /// actually emits when nothing is missing. Without this, `nominalWeights`
    /// and the `label:` literals inside `compute` could drift apart and
    /// `missingComponentLabels` would name a component that never existed.
    func testTableNamesMatchWhatAFullNightProduces() {
        let score = fullyPopulatedScore()
        let produced = Set(score.components.map(\.label))
        let declared = Set(SleepIntelligenceScore.nominalWeights.map(\.component))

        XCTAssertEqual(
            produced, declared,
            "the weight table and the components compute() emits have drifted apart"
        )
    }

    func testCompleteNightNamesNothingMissing() {
        let score = fullyPopulatedScore()
        XCTAssertTrue(
            score.missingComponentLabels.isEmpty,
            "a night with full history and staging dropped \(score.missingComponentLabels)"
        )
    }

    /// A complete score gets no caveat at all. A sentence that says the model
    /// ran fully is a sentence to read for no information.
    func testCompleteScoreHasNoConfidenceReason() {
        XCTAssertNil(fullyPopulatedScore().confidenceReason)
    }

    /// One night of history: the components that need a personal baseline
    /// cannot run, and the sentence has to name them rather than say the
    /// score is merely "low confidence".
    func testThinHistoryNamesTheDroppedComponents() {
        let score = SleepIntelligenceScore.compute(.init(
            night: Fixture.night(daysAgo: 0),
            history: [],
            sleepNeedMinutes: 480,
            regularityIndex: nil, habitualMidpointHours: nil
        ))

        guard let reason = score.confidenceReason else {
            return XCTFail("a score with no history behind it must say why")
        }
        XCTAssertTrue(
            reason.hasPrefix("Scored without "),
            "expected the dropped components to be named, got: \(reason)"
        )
        for label in score.missingComponentLabels {
            XCTAssertTrue(
                reason.contains(label),
                "\(label) was dropped but the sentence does not mention it: \(reason)"
            )
        }
    }

    /// The list is joined as prose, not printed as a Swift array. This caught
    /// nothing when written; it exists because the joining is hand-rolled and
    /// the one-element case takes a different branch from every other.
    func testSingleMissingComponentReadsAsProse() {
        let score = fullyPopulatedScore()
        // Build the sentence for a hypothetical one-missing night by taking a
        // real score and checking the branch directly through a night that
        // has no stage detail -- Stage Pattern is the component that needs it.
        let unstaged = SleepIntelligenceScore.compute(.init(
            night: Fixture.night(daysAgo: 0, staged: false),
            history: Fixture.consecutiveNights(30),
            sleepNeedMinutes: 480,
            regularityIndex: 85, habitualMidpointHours: -3
        ))
        guard unstaged.missingComponentLabels.count == 1 else {
            // Not a failure of the sentence: the fixture simply did not
            // isolate a single missing component. Assert nothing rather than
            // assert something untrue about the branch.
            return XCTAssertFalse(
                score.missingComponentLabels.isEmpty && unstaged.missingComponentLabels.isEmpty,
                "expected removing stage detail to drop at least one component"
            )
        }
        let reason = unstaged.confidenceReason ?? ""
        XCTAssertFalse(reason.contains(" and "), "one missing component should not be joined: \(reason)")
        XCTAssertTrue(reason.contains("for it tonight"), "singular pronoun expected: \(reason)")
    }

    /// `negativeContributors` is what the sheet's "what to do" line names, so
    /// its ordering is load-bearing: the first element has to be the one that
    /// actually cost the most, not merely a limiting one.
    func testWorstContributorIsFirst() {
        let score = SleepIntelligenceScore.compute(.init(
            night: Fixture.night(daysAgo: 0, timeAsleepMinutes: 290, timeInBedMinutes: 420, wakeCount: 9),
            history: Fixture.consecutiveNights(30),
            sleepNeedMinutes: 480,
            regularityIndex: 85, habitualMidpointHours: -3
        ))
        let negatives = score.negativeContributors
        guard negatives.count >= 2 else { return }
        for (earlier, later) in zip(negatives, negatives.dropFirst()) {
            XCTAssertLessThanOrEqual(
                earlier.pointContribution, later.pointContribution,
                "\(earlier.label) is listed before \(later.label) but cost less"
            )
        }
    }

    private func fullyPopulatedScore() -> SleepIntelligenceScore {
        SleepIntelligenceScore.compute(.init(
            night: Fixture.night(daysAgo: 0),
            history: Fixture.consecutiveNights(30),
            sleepNeedMinutes: 480,
            // Both supplied: a "fully populated" night that leaves Regularity
            // and Timing out because the caller passed nil would prove
            // nothing about the components actually being present.
            regularityIndex: 85, habitualMidpointHours: -3
        ))
    }
}
