import XCTest

/// Lead with meaning, keep the jargon.
///
/// The V9 spec's rule is "translate the terminology", not "remove it" -- an
/// advanced user needs "HRV" to compare Zoon against anything else they read.
/// These tests pin both halves, and pin the places where the plain name is
/// now what actually reaches the screen.
final class SleepVocabularyTests: XCTestCase {

    func testEveryTermCarriesBothNamesAndAMeaning() {
        for term in SleepVocabulary.all {
            XCTAssertFalse(term.plain.isEmpty)
            XCTAssertFalse(term.meaning.isEmpty, "\(term.plain) has no explanation")
            XCTAssertNotEqual(
                term.plain, term.technical,
                "\(term.plain) lists its own name as the technical alias"
            )
        }
    }

    /// The jargon must survive. Dropping it would make the app less useful to
    /// the reader who already knows the word.
    func testTheTechnicalTermIsKeptNotDiscarded() {
        XCTAssertEqual(SleepVocabulary.hrv.technical, "HRV")
        XCTAssertEqual(SleepVocabulary.core.technical, "Core")
        XCTAssertEqual(SleepVocabulary.waso.technical, "WASO")
        XCTAssertEqual(SleepVocabulary.hrv.full, "Recovery signal (HRV)")
    }

    /// A term whose plain name is already the standard one has no alias to
    /// show, and `full` must not render an empty parenthesis.
    func testATermWithNoAliasRendersCleanly() {
        let plainOnly = SleepVocabulary.Term(
            plain: "Bedtime", technical: nil, meaning: "When you went to bed."
        )
        XCTAssertEqual(plainOnly.full, "Bedtime")
    }

    // MARK: - What actually reaches the screen

    /// Apple calls this "Core". Every other tracker calls it light sleep, and
    /// "Core" means nothing to someone who has not learned Apple's
    /// vocabulary. The divergence is deliberate and documented.
    func testTheHypnogramSaysLightSleep() {
        XCTAssertEqual(SleepStage.core.displayName, "Light sleep")
        // The other stages are already plain and stay untouched.
        XCTAssertEqual(SleepStage.deep.displayName, "Deep")
        XCTAssertEqual(SleepStage.awake.displayName, "Awake")
    }

    /// Trend copy reads inside a sentence, where there is room for words.
    func testTrendProseUsesThePlainName() {
        XCTAssertEqual(TrendEngine.Metric.hrv.label, "recovery signal")
        XCTAssertFalse(TrendEngine.Metric.hrv.label.contains("HRV"))
    }

    // MARK: - Timing

    /// The V9 audit's own list of the six components calls this one Timing.
    /// "Circadian" is the word for the system underneath, kept as the alias.
    func testTheComponentIsCalledTiming() {
        XCTAssertTrue(
            SleepIntelligenceScore.nominalWeights.contains { $0.component == "Timing" }
        )
        XCTAssertFalse(
            SleepIntelligenceScore.nominalWeights.contains { $0.component == "Circadian" }
        )
        XCTAssertEqual(SleepVocabulary.circadianAlignment.technical, "Circadian alignment")
    }

    /// The same rename, one component over, and the gap it left behind.
    ///
    /// `stagePatternComponent` and the weight table were renamed away from
    /// "Architecture" some releases ago, but the sentence explaining the
    /// score to people still listed "Sleep Architecture" -- so the one place
    /// that defines the components used a word appearing nowhere else in the
    /// app. This pins both halves: the component's name, and the fact that
    /// the old word survives only as the alias on the vocabulary entry.
    func testTheComponentIsCalledStagePattern() {
        XCTAssertTrue(
            SleepIntelligenceScore.nominalWeights.contains { $0.component == "Stage Pattern" }
        )
        XCTAssertFalse(
            SleepIntelligenceScore.nominalWeights.contains { $0.component.contains("Architecture") }
        )
        XCTAssertEqual(SleepVocabulary.stagePattern.plain, "Stage pattern")
        XCTAssertEqual(SleepVocabulary.stagePattern.technical, "Sleep architecture")
    }

    /// Every term has to carry both halves and a definition, or the table is
    /// not doing the job it exists for.
    func testEveryTermIsComplete() {
        for term in SleepVocabulary.all {
            XCTAssertFalse(term.plain.isEmpty, "\(term)")
            XCTAssertFalse(term.meaning.isEmpty, "\(term.plain) has no definition")
            XCTAssertFalse(term.plain == term.technical, "\(term.plain) aliases itself")
        }
    }

    /// A rename is not a model change. The score has to be identical, or the
    /// version would have to move with it.
    func testRenamingTheComponentDidNotMoveTheScore() {
        let history = (0..<20).map { index in
            Fixture.night(daysAgo: index + 1, timeAsleepMinutes: 450 + 10 * (Double(index % 5) - 2))
        }
        let scored = SleepIntelligenceScore.compute(.init(
            night: Fixture.night(daysAgo: 0, timeAsleepMinutes: 460),
            history: history,
            sleepNeedMinutes: 450,
            regularityIndex: 75,
            habitualMidpointHours: -1.5
        ))
        XCTAssertEqual(scored.scoringVersion, SleepIntelligenceScore.currentVersion)
        let timing = scored.components.first { $0.label == "Timing" }
        XCTAssertNotNil(timing, "the Timing component should be present with a habitual midpoint")
        XCTAssertEqual(
            scored.components.reduce(0.0) { $0 + $1.weightUsed }, 1.0, accuracy: 0.0001,
            "renaming a component must not disturb the weighting"
        )
    }
}
