import Foundation

/// How well Zoon knows this person, area by area.
///
/// ## Why this is not a score
///
/// The V10 spec is blunt about it twice: *"Do NOT create another 0-100
/// score"*, and *"Do not create another score."* The temptation is obvious
/// -- coverage, baselines, evidence, calibration and matched support all
/// reduce to numbers, and a weighted sum of them would fit in a ring on the
/// Today screen. It would also be worthless. "Zoon knows you 82" tells you
/// nothing you can act on, hides which part is thin, and invites the one
/// behaviour this app should never encourage: watching a number go up.
///
/// So: four named stages, reported per area, with the count each was read
/// off. *Sleep need: well established, from 84 nights.* *Caffeine: still
/// learning, 4 of the 12 nights it needs.* That is a description of the
/// evidence, and the difference between the two framings is the difference
/// between somebody knowing what to do next and somebody being graded.
///
/// ## The overall stage is the weakest area, not the average
///
/// Averaging stages is a score with the numbers hidden. It also says the
/// wrong thing: a model that knows your sleep need cold and has never seen a
/// caffeinated night is not "moderately personalised", it is a model with a
/// hole in it, and the hole is the useful fact. `overall` takes the minimum
/// for that reason.
///
/// ## What it is read from
///
/// Every input is a count or an already-computed verdict, passed in. No
/// engine is re-run here and nothing is recomputed: this reports what the
/// rest of the app already decided, which is what keeps it from becoming a
/// second opinion that can disagree with the screens it summarises.
enum ModelHealth {

    // MARK: - Stages

    enum Stage: Int, Comparable, CaseIterable, Hashable, Sendable {
        /// Not yet enough to say anything personal.
        case learning = 0
        /// Enough for a first personal reading, thin enough to move.
        case establishing
        /// Settled enough to be about this person rather than about people.
        case personalised
        /// Long enough that a single odd fortnight will not move it.
        case wellEstablished

        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .learning: "Still learning"
            case .establishing: "Establishing"
            case .personalised: "Personalised"
            case .wellEstablished: "Well established"
            }
        }

        var meaning: String {
            switch self {
            case .learning:
                "Zoon is still collecting. Anything it says here is a general fact, not a fact about you."
            case .establishing:
                "There is a first personal reading here, and it will still move as more nights arrive."
            case .personalised:
                "This is about you now rather than about people in general."
            case .wellEstablished:
                "Settled enough that one unusual fortnight will not move it."
            }
        }
    }

    // MARK: - Areas

    enum Area: String, CaseIterable, Hashable, Sendable, Identifiable {
        case dataCoverage
        case sleepNeed
        case recoveryBaseline
        case bodySignals
        case behaviourEvidence
        case forecast
        case matchedComparisons

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dataCoverage: "What Zoon can see"
            case .sleepNeed: "Your sleep need"
            case .recoveryBaseline: "Your recovery baseline"
            case .bodySignals: "Your body-signal ranges"
            case .behaviourEvidence: "What your habits do"
            case .forecast: "How well its ranges hold up"
            case .matchedComparisons: "Comparing like with like"
            }
        }

        /// The question this area answers, in the person's words. Shown
        /// instead of a definition: "baseline maturity" is not a thing anyone
        /// wonders about.
        var question: String {
            switch self {
            case .dataCoverage: "How much of each night actually reaches Zoon?"
            case .sleepNeed: "How much sleep do you personally need?"
            case .recoveryBaseline: "What is a normal recovery night for you?"
            case .bodySignals: "What is a normal reading for you?"
            case .behaviourEvidence: "Which of your habits show up in your nights?"
            case .forecast: "When Zoon draws a range, do your nights land inside it?"
            case .matchedComparisons: "Can Zoon find nights like yours to compare against?"
            }
        }

        var symbol: String {
            switch self {
            case .dataCoverage: "dot.radiowaves.left.and.right"
            case .sleepNeed: "bed.double"
            case .recoveryBaseline: "heart"
            case .bodySignals: "waveform.path.ecg"
            case .behaviourEvidence: "list.bullet.clipboard"
            case .forecast: "target"
            case .matchedComparisons: "rectangle.on.rectangle"
            }
        }
    }

    // MARK: - Thresholds

    /// Nights behind a personal baseline, per stage.
    ///
    /// Fourteen is where `UncertaintyForecast` will first report a range at
    /// all, and twenty-eight is where `VitalsStatus.Metric.confidence` first
    /// calls a baseline moderate. Sixty is four times the first: two months
    /// of nights, past which one unusual fortnight is a quarter of the
    /// evidence rather than the half it was at twenty-eight.
    static let establishingNights = 14
    static let personalisedNights = 28
    static let wellEstablishedNights = 60

    /// Settled claims -- `.associated` or stronger -- behind "what your
    /// habits do".
    static let establishingClaims = 1
    static let personalisedClaims = 3
    static let wellEstablishedClaims = 6

    /// Matched pairs behind a supported comparison. Ten is the floor the
    /// matched estimator itself refuses below.
    static let establishingPairs = 10
    static let personalisedPairs = 18
    static let wellEstablishedPairs = 30

    /// Coverage below which the data itself is the limiting factor, whatever
    /// the night count says.
    static let thinCoverage = 0.6

    // MARK: - One area's reading

    struct Assessment: Identifiable, Hashable, Sendable {
        let area: Area
        let stage: Stage
        /// What the stage was read off, as a phrase. Always a count or a
        /// verdict, never a score: "from 84 nights", "4 of the 12 it needs".
        let basis: String

        var id: String { area.rawValue }
    }

    /// Places a count on the ladder.
    static func stage(for count: Int, establishing: Int, personalised: Int, wellEstablished: Int) -> Stage {
        switch count {
        case ..<establishing: .learning
        case ..<personalised: .establishing
        case ..<wellEstablished: .personalised
        default: .wellEstablished
        }
    }

    private static func nights(_ count: Int) -> String {
        "\(count) night\(count == 1 ? "" : "s")"
    }

    // MARK: - Assessing

    /// Every area, in a fixed order.
    ///
    /// - Parameters:
    ///   - nightCount: nights Zoon holds at all.
    ///   - nightsWithRecoverySignal: nights carrying an HRV reading -- what
    ///     the recovery baseline is actually built from, which is never the
    ///     same as the night count.
    ///   - nightsWithBodySignals: nights carrying resting heart rate.
    ///   - coverage: fraction of the measurements Zoon expects that actually
    ///     arrive, or nil when there is not yet enough to say.
    ///   - settledClaims: claims standing at `.associated` or stronger.
    ///   - calibration: the reliability verdict, or nil when there is not yet
    ///     enough history to backtest.
    ///   - matchedPairs: pairs behind the most recent supported matched
    ///     comparison, or nil when none was supported.
    static func assess(
        nightCount: Int,
        nightsWithRecoverySignal: Int,
        nightsWithBodySignals: Int,
        coverage: Double?,
        settledClaims: Int,
        calibration: CalibrationLedger.Verdict?,
        matchedPairs: Int?
    ) -> [Assessment] {
        [
            coverageAssessment(coverage: coverage, nightCount: nightCount),
            Assessment(
                area: .sleepNeed,
                stage: stage(
                    for: nightCount,
                    establishing: establishingNights,
                    personalised: personalisedNights,
                    wellEstablished: wellEstablishedNights
                ),
                basis: "From \(nights(nightCount))"
            ),
            Assessment(
                area: .recoveryBaseline,
                stage: stage(
                    for: nightsWithRecoverySignal,
                    establishing: establishingNights,
                    personalised: personalisedNights,
                    wellEstablished: wellEstablishedNights
                ),
                // Counted on the nights that carried a reading, not on every
                // night: a baseline cannot be built from a night that had
                // nothing to put in it, and quoting the larger number would
                // overstate exactly the areas with the least behind them.
                basis: "From \(nights(nightsWithRecoverySignal)) that carried a reading"
            ),
            Assessment(
                area: .bodySignals,
                stage: stage(
                    for: nightsWithBodySignals,
                    establishing: establishingNights,
                    personalised: personalisedNights,
                    wellEstablished: wellEstablishedNights
                ),
                basis: "From \(nights(nightsWithBodySignals)) that carried a reading"
            ),
            Assessment(
                area: .behaviourEvidence,
                stage: stage(
                    for: settledClaims,
                    establishing: establishingClaims,
                    personalised: personalisedClaims,
                    wellEstablished: wellEstablishedClaims
                ),
                basis: settledClaims == 0
                    ? "Nothing has separated from your ordinary nights yet"
                    : "\(settledClaims) habit\(settledClaims == 1 ? "" : "s") has shown up in your nights"
            ),
            forecastAssessment(calibration),
            matchedAssessment(matchedPairs)
        ]
    }

    /// Coverage is a fraction, and a fraction of very few nights is not a
    /// fraction worth reporting -- so this is capped by the night count as
    /// well. Both floors, whichever bites first.
    private static func coverageAssessment(coverage: Double?, nightCount: Int) -> Assessment {
        guard let coverage else {
            return Assessment(
                area: .dataCoverage,
                stage: .learning,
                basis: "Not enough nights yet to tell what is arriving"
            )
        }

        let percentage = Int((coverage * 100).rounded())
        let byCoverage: Stage = switch coverage {
        case ..<thinCoverage: .learning
        case ..<0.8: .establishing
        case ..<0.95: .personalised
        default: .wellEstablished
        }
        let byNights = stage(
            for: nightCount,
            establishing: establishingNights,
            personalised: personalisedNights,
            wellEstablished: wellEstablishedNights
        )

        return Assessment(
            area: .dataCoverage,
            stage: min(byCoverage, byNights),
            basis: "\(percentage)% of what Zoon looks for is arriving, over \(nights(nightCount))"
        )
    }

    /// A decisive-but-wrong calibration is `establishing`, not
    /// `personalised`.
    ///
    /// The verdict "your ranges are narrower than they should be" is a real
    /// finding, and it is a finding that the ranges are *wrong*. Ranking it
    /// alongside ranges that hold up would let a model be called personalised
    /// on the strength of knowing it is miscalibrated.
    private static func forecastAssessment(_ verdict: CalibrationLedger.Verdict?) -> Assessment {
        guard let verdict else {
            return Assessment(
                area: .forecast,
                stage: .learning,
                basis: "Not enough past nights to check its ranges against yet"
            )
        }
        let stage: Stage = switch verdict {
        case .notEnoughYet: .learning
        case .stillLearning: .establishing
        case .tooConfident, .tooCautious: .establishing
        case .matchesExpectation: .wellEstablished
        }
        return Assessment(area: .forecast, stage: stage, basis: verdict.label)
    }

    private static func matchedAssessment(_ pairs: Int?) -> Assessment {
        guard let pairs, pairs > 0 else {
            return Assessment(
                area: .matchedComparisons,
                stage: .learning,
                basis: "Zoon has not found enough comparable nights to compare yet"
            )
        }
        return Assessment(
            area: .matchedComparisons,
            stage: stage(
                for: pairs,
                establishing: establishingPairs,
                personalised: personalisedPairs,
                wellEstablished: wellEstablishedPairs
            ),
            basis: "\(pairs) matched pair\(pairs == 1 ? "" : "s") of your own nights"
        )
    }

    // MARK: - Overall

    /// The weakest area, not the average. See the type's own doc comment.
    static func overall(_ assessments: [Assessment]) -> Stage {
        assessments.map(\.stage).min() ?? .learning
    }

    /// What to say at the top: the overall stage, and which area is holding
    /// it there.
    static func headline(_ assessments: [Assessment]) -> String {
        let stage = overall(assessments)
        guard let weakest = assessments.first(where: { $0.stage == stage }) else {
            return stage.label
        }
        if assessments.allSatisfy({ $0.stage == stage }) {
            return "Every part of what Zoon knows about you is at the same point: \(stage.label.lowercased())."
        }
        return "Zoon knows some of this well. The part still holding it back is \(weakest.area.label.lowercased())."
    }
}
