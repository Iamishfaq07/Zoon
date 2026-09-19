import Foundation

/// The single action worth surfacing, chosen from everything the app could say.
///
/// Zoon has a lot of engines. `RecoveryDayPlan` has a view about today,
/// `LightCoach` about the morning, `NapCoach` about this afternoon,
/// `CaffeineCutoff` about this evening, `SleepAutopilot` about tonight. Each
/// is individually reasonable and collectively they are five imperatives on
/// one screen, which is not advice -- it is a list, and a list asks the
/// reader to do the prioritising the app was supposed to do.
///
/// So this ranks and picks one. The ranking is deliberately a product rather
/// than a sum: a candidate that scores zero on any single factor is not worth
/// saying, and a sum would let four strong factors carry a worthless fifth.
/// An action nobody can act on yet (`urgency` 0), or one that changes nothing
/// (`consequence` 0), or one already said yesterday (`novelty` 0), drops out
/// entirely rather than being averaged into contention.
///
/// **This does not generate advice.** Every candidate comes from an engine
/// that already decided the action was warranted on its own evidence. This
/// only decides which of them is worth the reader's one unit of attention,
/// and refuses when the answer is none of them.
enum OneThing {

    /// What a candidate is about. Used for contradiction rules and for
    /// recognising "the same advice as yesterday" across wording changes --
    /// two engines can phrase the same action differently, and novelty has to
    /// survive that.
    enum Kind: String, Codable, Sendable, CaseIterable {
        case protectWindow
        case skipLateNap
        case takeRecoveryNap
        case morningLight
        case reduceLoad
        case recoverAfterShortNight
        case moveCaffeineEarlier

        /// Actions that cannot both be the right answer at the same moment.
        ///
        /// Not a general "these are related" list: each pair is one the app
        /// could genuinely produce together, because two engines reason from
        /// different evidence and neither can see the other. Telling somebody
        /// to take a recovery nap and to skip a late nap in the same breath is
        /// the failure mode this exists for, and it is not hypothetical --
        /// `NapCoach` and the evening-protection path both fire on a day after
        /// a short night.
        var contradictions: Set<Kind> {
            switch self {
            case .skipLateNap: [.takeRecoveryNap]
            case .takeRecoveryNap: [.skipLateNap]
            // Protecting tonight's window and adding load today pull against
            // each other: one asks for an early evening, the other spends the
            // energy that makes an early evening possible.
            case .protectWindow: [.reduceLoad]
            case .reduceLoad: [.protectWindow]
            default: []
            }
        }
    }

    /// One engine's proposal, with the terms this ranks by.
    ///
    /// Every factor is 0...1 and every one is the proposing engine's
    /// judgment, not this type's. Nothing here re-derives whether the advice
    /// is sound; it only compares.
    struct Candidate: Sendable, Hashable, Identifiable {
        let kind: Kind
        var id: Kind { kind }

        /// The imperative, specific enough to act on without opening a screen.
        /// "Protect tonight's 10:45 PM window", not "get better sleep".
        let action: String

        /// Why *this* was chosen, in the reader's own numbers. The spec asks
        /// for the explanation and it is not decoration: an action whose
        /// reason cannot be stated is one the app cannot defend.
        let reason: String

        /// How much this helps if followed.
        let usefulness: Double
        /// How well the evidence behind it holds up.
        let confidence: MetricConfidence
        /// How soon it stops being actionable. A window three hours away is
        /// urgent; morning light at 9pm is not actionable at all.
        let urgency: Double
        /// How much it changes if ignored.
        let consequence: Double

        /// Clamped on the way in, so a miscomputed factor upstream cannot
        /// make one candidate outrank every other by arithmetic accident.
        init(
            kind: Kind,
            action: String,
            reason: String,
            usefulness: Double,
            confidence: MetricConfidence,
            urgency: Double,
            consequence: Double
        ) {
            self.kind = kind
            self.action = action
            self.reason = reason
            self.usefulness = Self.clamped(usefulness)
            self.confidence = confidence
            self.urgency = Self.clamped(urgency)
            self.consequence = Self.clamped(consequence)
        }

        private static func clamped(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(1, max(0, value))
        }
    }

    /// What was chosen, and what it beat.
    struct Selection: Sendable, Hashable {
        let candidate: Candidate
        let score: Double
        /// Everything suppressed, and why. Kept so the decision is
        /// inspectable rather than a number appearing from nowhere.
        let suppressed: [Suppression]
    }

    struct Suppression: Sendable, Hashable {
        enum Cause: String, Sendable {
            case lowConfidence
            case contradictedByWinner
            case repeatedRecently
            case scoredTooLow
            case outranked
        }
        let kind: Kind
        let cause: Cause
    }

    /// Below this, an action is a micro-optimisation rather than the one
    /// thing worth saying. The spec asks explicitly not to surface those.
    ///
    /// Set where a candidate at roughly half strength on all four numeric
    /// terms, with full confidence, still clears it comfortably (0.125),
    /// while one that is strong on three and near-worthless on the fourth
    /// falls out (0.9 x 0.9 x 0.05 = 0.04).
    ///
    /// It does not exclude everything with one weak term, and should not:
    /// the same candidate with the fourth term at 0.1 scores 0.08 and
    /// survives. The bar is against advice that is nearly pointless on some
    /// axis, not against advice that is merely uneven -- a genuinely useful,
    /// confident, urgent action with modest consequence is still the best
    /// thing to say on a quiet day.
    static let minimumScore = 0.06

    /// How much a night's advice decays for having been given recently.
    ///
    /// Not zero at one day: advice can legitimately repeat -- a second short
    /// night in a row genuinely still calls for recovery -- but it has to
    /// win by more to say the same thing twice, and saying it a third time
    /// needs more again.
    static func novelty(kind: Kind, recentlyShown: [Kind]) -> Double {
        let times = recentlyShown.filter { $0 == kind }.count
        switch times {
        case 0: return 1
        case 1: return 0.5
        case 2: return 0.2
        default: return 0
        }
    }

    /// Confidence as a multiplier. `.insufficient` is zero rather than small:
    /// the spec says not to surface low-confidence micro-optimisations, and
    /// an engine that cannot stand behind its own advice should not be
    /// competing for the one slot.
    static func weight(_ confidence: MetricConfidence) -> Double {
        switch confidence {
        case .insufficient: 0
        case .low: 0.5
        case .moderate: 0.8
        case .high: 1
        }
    }

    /// The product of the five terms.
    static func score(_ candidate: Candidate, recentlyShown: [Kind]) -> Double {
        candidate.usefulness
            * weight(candidate.confidence)
            * candidate.urgency
            * candidate.consequence
            * novelty(kind: candidate.kind, recentlyShown: recentlyShown)
    }

    /// Pick one, or none.
    ///
    /// - Parameters:
    ///   - candidates: every action the app's engines think is warranted now.
    ///   - recentlyShown: kinds surfaced on recent days, most recent first.
    ///     Kinds rather than strings, so rewording an action does not make it
    ///     novel again.
    ///
    /// Returning `nil` is a real answer and the common one on an ordinary
    /// day. A screen that must always name an action will invent one, and an
    /// invented imperative is worse than a quiet screen.
    static func choose(
        from candidates: [Candidate],
        recentlyShown: [Kind] = []
    ) -> Selection? {
        var suppressed: [Suppression] = []
        var contenders: [(Candidate, Double)] = []

        for candidate in candidates {
            guard candidate.confidence > .insufficient else {
                suppressed.append(.init(kind: candidate.kind, cause: .lowConfidence))
                continue
            }
            if novelty(kind: candidate.kind, recentlyShown: recentlyShown) == 0 {
                suppressed.append(.init(kind: candidate.kind, cause: .repeatedRecently))
                continue
            }
            let value = score(candidate, recentlyShown: recentlyShown)
            guard value >= minimumScore else {
                suppressed.append(.init(kind: candidate.kind, cause: .scoredTooLow))
                continue
            }
            contenders.append((candidate, value))
        }

        // Ties broken by kind rather than left to array order, so the same
        // inputs always produce the same answer. A recommendation that
        // changes when nothing changed reads as the app being unsure.
        let ranked = contenders.sorted { a, b in
            a.1 == b.1 ? a.0.kind.rawValue < b.0.kind.rawValue : a.1 > b.1
        }
        // Nothing cleared the bar. That is a real answer, not a failure to
        // find one, and the caller shows nothing rather than the best of a
        // bad set.
        guard let (winner, winningScore) = ranked.first else { return nil }

        for (other, _) in ranked.dropFirst() {
            let cause: Suppression.Cause = winner.kind.contradictions.contains(other.kind)
                ? .contradictedByWinner
                : .outranked
            suppressed.append(.init(kind: other.kind, cause: cause))
        }

        return Selection(candidate: winner, score: winningScore, suppressed: suppressed)
    }
}
