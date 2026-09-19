import Foundation

/// What one Recovery driver contributed, for the hero's centre when it is
/// tapped.
///
/// The radar's perimeter icons have been tappable since the marker overlap was
/// fixed, and tapping one selected it and changed nothing else. This is what
/// selecting is *for*: the centre stops showing the score and shows what that
/// signal read, how it compares to the person's own baseline, and how much of
/// today's score it actually carried.
///
/// **Why `effectiveWeight` and not `weight`.** `RecoveryScore` publishes both:
/// the nominal share from its table, and the share a component carried after
/// the missing ones' weight was redistributed. The spec asks for "today's
/// Recovery weighting", and on a night where respiratory rate never arrived,
/// HRV genuinely carried more than its table row says. Printing the nominal
/// number would be describing a scoring model rather than this night, and the
/// two differ exactly when the reader most needs the truth -- when something
/// was missing.
enum ScoreAnatomy {

    /// One driver, expanded.
    struct Detail: Sendable, Hashable, Identifiable {
        let label: String
        var id: String { label }

        /// The reading itself: "50 ms", or "—" when nothing arrived.
        let value: String
        /// How it sits against this person's own baseline, in the wording
        /// `RecoveryDriverSemantics` already established. Not re-derived here:
        /// two phrasings of the same comparison is how a screen starts
        /// contradicting itself.
        let comparison: String
        /// "45% of today's Recovery weighting", or the honest alternative when
        /// it carried none.
        let contribution: String
        /// The same, shortened for the ring's centre.
        let compactContribution: String
        /// Whether a reading arrived at all.
        let isAvailable: Bool
    }

    /// Rounded for display. A weight of 0.452 is 45%, and the extra digits
    /// would imply a precision the scoring table does not have.
    static func percent(_ effectiveWeight: Double) -> Int {
        guard effectiveWeight.isFinite else { return 0 }
        return Int((min(1, max(0, effectiveWeight)) * 100).rounded())
    }

    /// How this component's share is stated.
    ///
    /// A component that carried nothing says so rather than printing "0% of
    /// today's Recovery weighting", which reads as a measured contribution of
    /// zero -- the same "missing is not zero" failure the watch's recovery
    /// dial had, in a sentence instead of a number.
    static func contribution(for component: RecoveryScore.Component) -> String {
        guard component.isAvailable else {
            return "Not counted in today's score"
        }
        let share = percent(component.effectiveWeight)
        guard share > 0 else { return "Not counted in today's score" }
        return "\(share)% of today's Recovery weighting"
    }

    /// The same fact in the room the ring's centre has.
    ///
    /// That centre is capped at just over half the ring's width so the text
    /// cannot reach the radar vertices sitting level with it -- a constraint
    /// the view documents at length, having already been bitten by
    /// "15.1 br/min" reaching them. "45% of today's Recovery weighting" is
    /// twice the length of what fits. The long form stays for VoiceOver and
    /// for surfaces with room; inside the ring it is unambiguous which score
    /// is meant.
    static func compactContribution(for component: RecoveryScore.Component) -> String {
        guard component.isAvailable, percent(component.effectiveWeight) > 0 else {
            return "Carries no weight today"
        }
        return "\(percent(component.effectiveWeight))% of the score"
    }

    static func detail(for component: RecoveryScore.Component) -> Detail {
        Detail(
            label: component.label,
            value: component.isAvailable ? component.detail : "—",
            comparison: RecoveryDriverSemantics.reading(for: component).phrase,
            contribution: contribution(for: component),
            compactContribution: compactContribution(for: component),
            isAvailable: component.isAvailable
        )
    }

    /// The whole anatomy, in the order the radar draws its perimeter.
    static func details(for components: [RecoveryScore.Component]) -> [Detail] {
        components.map(detail(for:))
    }

    /// Spoken as one sentence, so VoiceOver does not read four fragments and
    /// leave the listener to assemble them.
    static func accessibilityLabel(for component: RecoveryScore.Component) -> String {
        let detail = detail(for: component)
        guard detail.isAvailable else {
            return "\(detail.label). \(detail.comparison). \(detail.contribution)."
        }
        return "\(detail.label), \(RecoveryDriverSemantics.spokenReading(component.detail)). "
            + "\(detail.comparison). \(detail.contribution)."
    }
}
