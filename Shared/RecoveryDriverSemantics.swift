import Foundation

/// What each Recovery driver's number actually means, in words that match it.
///
/// **The defect this replaces.** `ScoreDrivers` put one scale under all four
/// signals:
///
/// ```swift
/// switch component.normalized {
/// case ..<0.35: "Low"
/// case ..<0.55: "Fair"
/// case ..<0.78: "Good"
/// default:      "Optimal"
/// }
/// ```
///
/// The four `normalized` values are not on the same scale, because they are
/// not answering the same question. From `RecoveryScore.compute`:
///
/// | Signal      | Formula                  | At the person's own baseline |
/// |-------------|--------------------------|------------------------------|
/// | HRV         | `0.5 + deviation / 0.5`  | **0.50** |
/// | Resting HR  | `0.5 - deviation / 0.24` | **0.50** |
/// | Respiratory | `1 - abs(delta) / 1.5`   | **1.00** |
/// | Sleep       | `performance / 100`      | 0.82 at 82% of need |
///
/// So somebody whose HRV and resting heart rate were exactly normal for them
/// read "Fair" on both, while their respiration read "Optimal" for being
/// equally normal, and 82% of their sleep need read "Optimal" too. The words
/// were not describing the body; they were describing four different
/// arithmetic conventions.
///
/// **What replaces it.** Each signal gets wording in its own terms. Nothing
/// here is a verdict on the person: HRV and resting heart rate are stated as
/// a relationship to their own baseline, respiration as inside or outside its
/// usual range, and sleep against the target it was measured against.
///
/// No signal says "Optimal". A single overnight reading from a consumer
/// wearable does not establish that anything is optimal, and the word was
/// doing the most work on exactly the two signals — respiration and sleep —
/// where it was least earned.
enum RecoveryDriverSemantics {

    /// Which of the four, resolved from the component's label.
    ///
    /// `RecoveryScore` builds its components with these labels, and they are
    /// what the whole app keys on. Matching them here rather than adding a
    /// case to `Component` keeps this a presentation concern.
    enum Driver: String, CaseIterable, Sendable {
        case hrv = "HRV"
        case restingHeartRate = "Resting HR"
        case sleep = "Sleep"
        case respiratory = "Respiratory"

        static func named(_ label: String) -> Driver? { Driver(rawValue: label) }
    }

    /// Where a reading sits, as a fact rather than a grade.
    enum Standing: Hashable, Sendable {
        /// Close enough to this person's own normal that the difference is
        /// not worth a word.
        case typical
        /// Away from their normal, in the direction that matters for this
        /// signal.
        case notable
        /// Away from their normal in the other direction — real, and not a
        /// concern.
        case favourable
        /// There was no reading.
        case unmeasured

        /// Whether this is worth spending colour on.
        ///
        /// Only `notable` is. The brief's instruction is not to run four
        /// red/green verdict systems under a hero that is already a gradient
        /// — so "typical" and "favourable" stay in ordinary ink, and the one
        /// state a reader might act on is the one that stands out.
        var deservesEmphasis: Bool { self == .notable }
    }

    struct Reading: Hashable, Sendable {
        let standing: Standing
        /// The line shown under the number.
        let phrase: String
        /// The same thing said for VoiceOver, where "below your baseline"
        /// has to carry on its own without the number beside it.
        let spokenPhrase: String
    }

    // MARK: - Where "near enough" stops

    /// How far from baseline still counts as typical, in units of each
    /// signal's own scoring scale.
    ///
    /// A fifth of the scale each way. `RecoveryScore` spans HRV across ±25%
    /// of baseline and resting heart rate across ±12%, so this lands at
    /// roughly ±5% for HRV and ±2.4% for resting heart rate — both inside the
    /// night-to-night wobble either signal shows in a person who has changed
    /// nothing, which is the point. A band that called every 3% HRV dip
    /// "below your baseline" would be reporting noise back as news.
    static let typicalBand = 0.10

    /// Respiration is scored on absolute departure rather than percentage,
    /// and is stable enough night to night that half a breath per minute is
    /// already worth naming. `1 - 0.5/1.5` is the normalized equivalent.
    static let respiratoryTypicalNormalized = 1 - 0.5 / 1.5

    /// Sleep at or above this fraction of its target counts as met.
    ///
    /// Not 1.0: a target built from a heuristic model does not deserve to be
    /// missed by four minutes. `SleepNeed` is a planning estimate, and
    /// treating it as a threshold to the minute would give it a precision it
    /// has not got.
    static let sleepMetFraction = 0.95

    /// Below this, the night was short enough to say so.
    static let sleepShortFraction = 0.85

    // MARK: - Reading a component

    static func reading(for component: RecoveryScore.Component) -> Reading {
        guard component.isAvailable else {
            return Reading(
                standing: .unmeasured,
                phrase: "Not measured",
                spokenPhrase: "not measured"
            )
        }
        guard let driver = Driver.named(component.label) else {
            // A signal this file has not been taught about says the least it
            // can rather than borrowing another signal's words.
            return Reading(standing: .typical, phrase: "Recorded", spokenPhrase: "recorded")
        }

        return switch driver {
        case .hrv: hrvReading(component)
        case .restingHeartRate: restingHeartRateReading(component)
        case .sleep: sleepReading(component)
        case .respiratory: respiratoryReading(component)
        }
    }

    /// HRV is scored as deviation from this person's own baseline, so that is
    /// what the words say. Never "optimal": HRV is meaningless between people
    /// and a good night for one person is another's bad one.
    private static func hrvReading(_ component: RecoveryScore.Component) -> Reading {
        let distance = component.normalized - 0.5
        if abs(distance) <= typicalBand {
            return Reading(standing: .typical, phrase: "Near baseline", spokenPhrase: "near your baseline")
        }
        return distance > 0
            ? Reading(standing: .favourable, phrase: "Above your baseline", spokenPhrase: "above your baseline")
            : Reading(standing: .notable, phrase: "Below your baseline", spokenPhrase: "below your baseline")
    }

    /// Resting heart rate runs the other way — higher than baseline is the
    /// unfavourable direction — but the wording stays descriptive either way,
    /// so a reader is told what happened rather than graded on it.
    private static func restingHeartRateReading(_ component: RecoveryScore.Component) -> Reading {
        let distance = component.normalized - 0.5
        if abs(distance) <= typicalBand {
            return Reading(standing: .typical, phrase: "Near baseline", spokenPhrase: "near your baseline")
        }
        // The scale is inverted, so a *high* normalized value is a low rate.
        return distance > 0
            ? Reading(standing: .favourable, phrase: "Below your baseline", spokenPhrase: "below your baseline")
            : Reading(standing: .notable, phrase: "Above your baseline", spokenPhrase: "above your baseline")
    }

    /// The reading beside this already says "82% of need", so the line under
    /// it only has to say which side of the target that is — not grade it.
    /// 82% of a target is not "Optimal" under any reading of the word.
    private static func sleepReading(_ component: RecoveryScore.Component) -> Reading {
        if component.normalized >= sleepMetFraction {
            return Reading(standing: .typical, phrase: "Target met", spokenPhrase: "target met")
        }
        if component.normalized >= sleepShortFraction {
            return Reading(standing: .typical, phrase: "Near target", spokenPhrase: "near your target")
        }
        return Reading(standing: .notable, phrase: "Below target", spokenPhrase: "below your target")
    }

    /// Respiration is scored on how far it sat from its usual, in either
    /// direction, so "within usual range" is the honest resting state — not
    /// "Optimal", which is what a normalized 1.0 used to produce for a person
    /// whose breathing was simply unremarkable.
    private static func respiratoryReading(_ component: RecoveryScore.Component) -> Reading {
        if component.normalized >= respiratoryTypicalNormalized {
            return Reading(
                standing: .typical,
                phrase: "Within usual range",
                spokenPhrase: "within your usual range"
            )
        }
        let raised = (component.deviationPercent ?? 0) > 0
        return Reading(
            standing: .notable,
            phrase: raised ? "Above usual range" : "Below usual range",
            spokenPhrase: raised ? "above your usual range" : "below your usual range"
        )
    }

    // MARK: - Speaking the number

    /// The reading with its unit spelled out.
    ///
    /// VoiceOver says "ms" as "em ess" and "br/min" as "bee are slash min".
    /// The abbreviations are right on screen, where space is short and the
    /// reader can see them; they are wrong out loud.
    static func spokenReading(_ detail: String) -> String {
        var spoken = detail
        for (abbreviation, spelled) in [
            ("br/min", "breaths per minute"),
            ("bpm", "beats per minute"),
            ("ms", "milliseconds")
        ] where spoken.hasSuffix(abbreviation) {
            spoken = spoken.replacingOccurrences(
                of: abbreviation, with: spelled, options: .backwards
            )
            break
        }
        return spoken
    }

    /// The whole spoken description for one driver.
    ///
    /// "HRV, 50 milliseconds, below your baseline" — the relationship, not a
    /// grade. "HRV, 50 milliseconds, low" told a reader nothing about what
    /// low meant, and for HRV there is no population answer to that question.
    static func accessibilityLabel(for component: RecoveryScore.Component) -> String {
        let reading = reading(for: component)
        guard component.isAvailable else {
            return "\(component.label), not measured"
        }
        return "\(component.label), \(spokenReading(component.detail)), \(reading.spokenPhrase)"
    }
}
