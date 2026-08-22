import Foundation

/// "What's usually present before my best sleep" -- a different question
/// from anything Cause Finder answers.
///
/// Cause Finder starts from a behaviour and asks whether it's associated
/// with better or worse outcomes (a matched-pair hypothesis test, one tag at
/// a time). The Playbook starts from the *nights themselves*: it finds the
/// best quarter of nights on record, then asks which conditions showed up
/// disproportionately often around them versus the rest of history. Both are
/// still correlation, not causation, and both say so -- but this is a
/// genuinely different statistical framing, not a re-presentation of Cause
/// Finder's own findings.
///
/// Built only from data with enough history behind it: below
/// `minimumNights` this produces nothing at all, and any individual factor
/// below its own sample floor or effect-size floor is silently excluded
/// rather than padded in with a low-confidence caveat -- a playbook item
/// nobody can act on yet is worse than no playbook item.
struct SleepPlaybook: Sendable {

    struct Factor: Identifiable, Sendable {
        let id: String
        let label: String
        /// Fraction of best nights (0...1) this factor was present for.
        let bestNightsRate: Double
        /// Fraction of *non-best* known nights (0...1) it was present for --
        /// the baseline `bestNightsRate` is compared against. Deliberately
        /// excludes the best nights themselves, otherwise a factor present
        /// on every best night still shows a "typical" rate inflated by
        /// those same nights, understating the real gap.
        let otherNightsRate: Double
        let sampleSize: Int
        /// How much to trust this factor's rates, from its best-nights
        /// sample size and how wide the gap is -- a factor that only just
        /// clears the floors is real but thin, not the same confidence as
        /// one with a big sample and a wide gap.
        let confidence: MetricConfidence
    }

    /// One candidate condition to test against the best-nights split.
    struct FactorInput: Sendable {
        let id: String
        let label: String
        /// Per-night presence, in the same order as the outcome array
        /// passed to `build`. `nil` where presence is unknown for that
        /// night -- excluded from both rates entirely rather than counted
        /// as absent, since an unknown is not evidence either way.
        let presencePerNight: [Bool?]
    }

    let factors: [Factor]

    /// Nights required before a "best quarter" is even meaningful to draw.
    static let minimumNights = 21
    /// A factor needs at least this many *known* nights (present or
    /// absent, not unknown) before its rates mean anything.
    static let minimumKnownNights = 21
    /// A factor needs at least this many known nights *within the best
    /// quarter specifically* -- otherwise a rate computed from two or
    /// three best nights is noise dressed up as a percentage.
    static let minimumBestNightsSample = 3
    /// How far `bestNightsRate` has to diverge from `typicalRate` before
    /// it's worth showing -- a 4-point gap is noise, a 20-point one is a
    /// real pattern.
    static let minimumEffectGap = 0.2

    /// - Parameters:
    ///   - outcomePerNight: the metric used to rank nights, e.g. sleep
    ///     performance -- higher is better. Same length and order as
    ///     `presencePerNight` in every `FactorInput`.
    ///   - factorInputs: every candidate condition to test.
    static func build(outcomePerNight: [Double], factorInputs: [FactorInput]) -> SleepPlaybook? {
        guard outcomePerNight.count >= minimumNights else { return nil }

        let bestCount = max(minimumBestNightsSample, outcomePerNight.count / 4)
        let bestIndices = Set(
            outcomePerNight.indices
                .sorted { outcomePerNight[$0] > outcomePerNight[$1] }
                .prefix(bestCount)
        )

        var factors: [Factor] = []
        for input in factorInputs {
            let known = input.presencePerNight.enumerated().compactMap { index, value in
                value.map { (index: index, present: $0) }
            }
            guard known.count >= minimumKnownNights else { continue }

            let bestKnown = known.filter { bestIndices.contains($0.index) }
            let otherKnown = known.filter { !bestIndices.contains($0.index) }
            guard bestKnown.count >= minimumBestNightsSample, !otherKnown.isEmpty else { continue }

            let bestRate = Double(bestKnown.filter(\.present).count) / Double(bestKnown.count)
            let otherRate = Double(otherKnown.filter(\.present).count) / Double(otherKnown.count)
            let gap = abs(bestRate - otherRate)
            guard gap >= minimumEffectGap else { continue }

            let confidence: MetricConfidence
            if bestKnown.count >= 8, gap >= 0.35 {
                confidence = .high
            } else if bestKnown.count >= 5, gap >= 0.25 {
                confidence = .moderate
            } else {
                confidence = .low
            }

            factors.append(Factor(
                id: input.id, label: input.label,
                bestNightsRate: bestRate, otherNightsRate: otherRate,
                sampleSize: bestKnown.count, confidence: confidence
            ))
        }

        return SleepPlaybook(
            factors: factors.sorted { abs($0.bestNightsRate - $0.otherNightsRate) > abs($1.bestNightsRate - $1.otherNightsRate) }
        )
    }
}
