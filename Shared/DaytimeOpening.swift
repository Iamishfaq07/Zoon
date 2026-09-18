import Foundation

/// The sentence at the top of Today, composed so that each half says when it
/// is talking about.
///
/// **The trust problem this fixes.** At ten past two in the afternoon the
/// screen said:
///
/// ```text
/// Ishfaq, your body needs moderate output today.
/// ```
///
/// derived entirely from `RecoveryScore.band` — a score `RecoveryScore` itself
/// documents as *"scored from last night. It doesn't move during the day."*
/// Both statements cannot be the product's daytime semantics. One says the
/// number is a fixed record of the morning; the other spends it as a live
/// instruction about the afternoon.
///
/// The number was never wrong. What was wrong was the tense: a reading taken
/// at 07:00 was being read out at 14:10 as though it had just been measured,
/// and by then the person had had a day the score knew nothing about.
///
/// **What this does instead.** Two clauses, each tied to its own moment:
///
/// ```text
/// Morning Recovery was moderate. Your physiological load is typical right now.
/// ```
///
/// The first is past tense because it is about the morning. The second is
/// present tense because it comes from `StressScore`, which is computed from
/// quiet daytime readings and does move. Where there is no current reading
/// yet, the second clause says so rather than borrowing the first one's
/// confidence — an afternoon with no quiet minutes in it is a real state.
///
/// **No new score.** This composes what already exists. The app has Morning
/// Recovery, Energy, Daily Load and Physiological Load, and the brief is
/// explicit that a fifth 0–100 number needs its own justification rather than
/// arriving because a sentence was awkward.
///
/// **Guidance is withheld unless both halves agree.** "Keep today easy" is a
/// claim about now, and a morning score cannot make it alone. It is offered
/// only when the overnight reading and the current one point the same way,
/// which is the only case where the evidence covers the sentence.
enum DaytimeOpening {

    /// What the current physiological reading is allowed to contribute.
    ///
    /// Deliberately a small vocabulary. `StressScore` bands are calm,
    /// elevated and high; these restate them as a relationship to the
    /// person's own usual, which is what the band already means.
    enum CurrentState: Sendable, Hashable {
        case aroundUsual
        case raised
        case wellAbove
        /// Not enough quiet daytime readings yet. Not the same as calm.
        case unknown

        init(band: StressScore.Band?) {
            switch band {
            case .calm: self = .aroundUsual
            case .elevated: self = .raised
            case .high: self = .wellAbove
            case nil: self = .unknown
            }
        }

        var clause: String {
            switch self {
            case .aroundUsual: "your physiological load is around your usual right now"
            case .raised: "your physiological load is running a little high right now"
            case .wellAbove: "your physiological load is well above your usual right now"
            case .unknown: "there are not enough quiet daytime readings yet to say how today is going"
            }
        }
    }

    /// How the overnight reading is stated: past tense, about the morning,
    /// and about signals rather than about the person.
    ///
    /// The old `Band.guidance` said "Primed. Your body looks ready for a
    /// harder session today" — which is a training prescription derived from
    /// four overnight numbers off a consumer wearable, and reaches well past
    /// what they establish.
    static func morningClause(band: RecoveryScore.Band) -> String {
        switch band {
        case .high: "Morning Recovery was high"
        case .moderate: "Morning Recovery was moderate"
        case .low: "Morning Recovery was low"
        }
    }

    /// The composed opening.
    ///
    /// - Parameters:
    ///   - band: the overnight reading, or `nil` when the score is being
    ///     withheld — in which case nothing here invents one.
    ///   - currentBand: `StressScore.band` for today, when there is one.
    ///   - name: the person's own name, when they have set one. Empty is a
    ///     real answer and nothing here nags for it.
    static func sentence(
        band: RecoveryScore.Band?,
        currentBand: StressScore.Band?,
        name: String = ""
    ) -> String {
        let current = CurrentState(band: currentBand)

        guard let band else {
            // The score is withheld. The current reading can still be stated
            // — it is measured independently — but nothing pretends to know
            // how the night went.
            let line = current == .unknown
                ? "here is last night. Recovery needs more physiological data before it can say how you woke."
                : "here is last night. Recovery needs more physiological data before it can say how you woke, but \(current.clause)."
            return address(line, name: name)
        }

        return address("\(morningClause(band: band)). \(current.clause).", name: name, capitalised: true)
    }

    /// A line the person can act on, or `nil`.
    ///
    /// Offered only when the morning and the present agree. A low morning
    /// under an ordinary afternoon is not evidence for "take it easy" — the
    /// afternoon is the half that would have to support that, and it is not
    /// supporting it. Likewise a high morning does not license a hard session
    /// once the current reading has gone well above usual.
    static func guidance(band: RecoveryScore.Band?, currentBand: StressScore.Band?) -> String? {
        guard let band else { return nil }
        switch (band, CurrentState(band: currentBand)) {
        case (.low, .raised), (.low, .wellAbove), (.moderate, .wellAbove):
            return "Last night and today are pointing the same way. A lighter day is the safer read."
        case (.high, .aroundUsual):
            return "Last night's signals and today's are both around or above your usual."
        default:
            return nil
        }
    }

    /// Prefixes the name when there is one, and capitalises otherwise.
    private static func address(_ line: String, name: String, capitalised: Bool = false) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return capitalised ? line : line.prefix(1).uppercased() + line.dropFirst()
        }
        let body = capitalised ? line.prefix(1).lowercased() + line.dropFirst() : line
        return "\(trimmed), \(body)"
    }
}
