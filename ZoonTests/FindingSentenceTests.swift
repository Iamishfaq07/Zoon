import XCTest

/// What a matched-pair finding is allowed to say.
///
/// The wording *is* the claim. "Late caffeine makes your sleep worse" and "on
/// nights you logged late caffeine, your sleep tends to be worse" are
/// different statements, and only the second is what a matched-pair
/// comparison over someone's own history supports.
final class FindingSentenceTests: XCTestCase {

    private func sentence(improvement: Bool) -> String {
        FindingSentence.association(
            behaviour: "Late caffeine",
            outcome: "Sleep efficiency",
            isImprovement: improvement
        )
    }

    func testTheSentenceStatesAnAssociationNotACause() {
        let worse = sentence(improvement: false)
        XCTAssertEqual(
            worse,
            "On nights you logged late caffeine, your sleep efficiency tends to be worse."
        )
        for banned in ["cause", "makes", "leads to", "because", "due to", "results in"] {
            XCTAssertFalse(
                worse.lowercased().contains(banned),
                "\(banned) claims more than a matched-pair comparison supports: \(worse)"
            )
        }
    }

    func testDirectionFollowsTheFinding() {
        XCTAssertTrue(sentence(improvement: true).hasSuffix("tends to be better."))
        XCTAssertTrue(sentence(improvement: false).hasSuffix("tends to be worse."))
    }

    /// Both halves are lowercased into the sentence, so a tag or metric whose
    /// display name is capitalised does not read as a proper noun mid-clause.
    func testNamesReadAsProseNotAsLabels() {
        let result = sentence(improvement: true)
        XCTAssertTrue(result.contains("late caffeine"), result)
        XCTAssertTrue(result.contains("sleep efficiency"), result)
        XCTAssertFalse(result.contains("Late caffeine"), result)
    }

    // MARK: - Support line

    /// The count is always shown. A finding from 6 matched nights and one
    /// from 60 read identically without it, and the number is the single most
    /// useful thing for deciding whether to act on one.
    func testSupportAlwaysCarriesTheSampleSize() {
        XCTAssertEqual(
            FindingSentence.support(matchedPairCount: 18, confidence: "Moderate confidence"),
            "18 matched nights · Moderate confidence"
        )
    }

    func testASingleNightIsNotPluralised() {
        XCTAssertEqual(
            FindingSentence.support(matchedPairCount: 1, confidence: "Low confidence"),
            "1 matched night · Low confidence"
        )
    }

    func testZeroIsStillStatedRatherThanHidden() {
        let result = FindingSentence.support(matchedPairCount: 0, confidence: "Low confidence")
        XCTAssertTrue(result.hasPrefix("0 matched nights"), result)
    }
}
