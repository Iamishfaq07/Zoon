import Foundation

/// A matched-pair finding, said in a sentence rather than a statistic.
///
/// ## Why this is not in the view
///
/// Every sentence here is an association claim about someone's own data, and
/// the wording is the claim. "Late caffeine makes your sleep worse" and "on
/// nights you logged late caffeine, your sleep tends to be worse" are
/// different statements, and only the second one is what a matched-pair
/// comparison supports. Copy that makes claims belongs somewhere it can be
/// tested, and a `Text(...)` is not that place -- the same reasoning behind
/// `MorningInThree` and `InsightLanguageTests`.
///
/// ## Why it takes primitives
///
/// `JournalCorrelator.Finding` lives in the app target and reaches
/// `BehaviorTag`, `BehaviorObservation` and the rest of the journal stack.
/// Pulling all of that into the test target to assert a sentence would be a
/// large dependency for a small string. Taking the four things the sentence
/// actually depends on keeps the wording testable on its own, and
/// `Finding.plainSentence` is a one-line call.
enum FindingSentence {

    /// - Parameters:
    ///   - behaviour: the tag's display name, e.g. "Late caffeine".
    ///   - outcome: what was measured, e.g. "sleep duration".
    ///   - isImprovement: whether the tagged nights came out better on that
    ///     outcome, already resolved for metrics where lower is better.
    static func association(
        behaviour: String,
        outcome: String,
        isImprovement: Bool
    ) -> String {
        // "tends to" rather than "is", and "on nights you logged" rather than
        // a bare causal verb. A matched-pair comparison over someone's own
        // history supports an association and a direction. It does not
        // support "caused", and the difference is four words wide.
        let direction = isImprovement ? "better" : "worse"
        return "On nights you logged \(behaviour.lowercased()), your \(outcome.lowercased()) tends to be \(direction)."
    }

    /// The evidence line under the sentence: how much was compared, and how
    /// much to believe it.
    ///
    /// The count is always shown. A finding from 6 matched nights and one
    /// from 60 read identically without it, and the number is the single
    /// most useful thing for deciding whether to act on one.
    static func support(matchedPairCount: Int, confidence: String) -> String {
        let nights = matchedPairCount == 1 ? "1 matched night" : "\(matchedPairCount) matched nights"
        return "\(nights) · \(confidence)"
    }
}
