import Foundation

/// Whether today calls for backing off, and why.
///
/// Distinct from just reading `RecoveryScore.band == .low`: that's one
/// automatic signal derived from last night's vitals, and vitals lag
/// reality -- a stomach bug or a bad night's sleep from stress doesn't
/// always show up in HRV the very next morning. Recovery Mode gives that
/// state a name, a consistent place in the UI, and a manual override the
/// user can set for themselves rather than only ever reading it off a
/// score they didn't ask to see explained.
///
/// Deliberately UI/copy scope only for this first pass: it does not
/// suppress notifications, alter the wake-window nudge, or change any
/// score's computation. See `RecoveryModeCard`.
struct RecoveryMode: Sendable, Hashable {

    enum Source: Sendable, Hashable {
        /// `RecoveryScore.band == .low` for last night.
        case autoSuggested
        /// The user turned it on for today, independent of the score.
        case manuallyEnabled
    }

    let source: Source

    /// `nil` when neither condition holds -- there is no "inactive"
    /// `RecoveryMode` value on purpose, so a caller can't forget to check
    /// before showing the card.
    static func evaluate(band: RecoveryScore.Band, manuallyEnabledToday: Bool) -> RecoveryMode? {
        if manuallyEnabledToday { return RecoveryMode(source: .manuallyEnabled) }
        if band == .low { return RecoveryMode(source: .autoSuggested) }
        return nil
    }

    var headline: String { "Recovery Mode" }

    var detail: String {
        switch source {
        case .autoSuggested:
            "Your vitals suggest your body is still working through last night. Today's a good day to keep training easy and prioritise sleep tonight."
        case .manuallyEnabled:
            "You've marked today as a recovery day. Take it easy, regardless of what the numbers say -- you know things about today they can't measure."
        }
    }

    /// Whether the manual "turn it off" affordance makes sense. Auto-suggested
    /// mode isn't something to dismiss -- it's just an honest read of last
    /// night's vitals, and it stops being active on its own once they recover.
    var isDismissible: Bool { source == .manuallyEnabled }
}
