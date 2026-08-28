import Foundation

/// Shared backstop against diagnostic language reaching the screen from any
/// on-device model output.
///
/// `FoundationModelInsightEngine` and `CoachChat` both generate free text
/// from the same on-device model, and both prompt it never to diagnose or
/// name a condition. A prompt instruction is a request the model may or may
/// not honour every single turn, not a guarantee -- this is the structural
/// check that runs after generation regardless of what the model actually
/// produced, so a lapse in one bad response can't reach a screen where it
/// would read as a medical claim this app has no business making.
enum DiagnosticLanguageGuard {

    /// Diagnostic language this app must never produce.
    static let bannedTerms = [
        "apnea", "apnoea", "insomnia", "narcolepsy", "diagnos",
        "disorder", "syndrome", "disease", "you should see a doctor"
    ]

    /// Prescriptive health actions that are unsafe for a wellness model to
    /// improvise even when it avoids naming a diagnosis.
    static let unsafeGuidanceTerms = [
        "stop taking", "start taking", "change your dose", "increase your dose",
        "decrease your dose", "skip your medication", "replace your medication",
        "sleep fewer than", "stay awake all night", "ignore chest pain"
    ]

    /// Phrasing that asserts a cause, a mechanism, or a readiness verdict
    /// Zoon has not established.
    ///
    /// Zoon's rules observe things co-occurring on a single night. That is
    /// not evidence one produced the other, and the difference is the whole
    /// epistemic position of the app -- `JournalCorrelator` goes to
    /// considerable trouble over matched pairs and bootstrap intervals
    /// precisely because a co-occurrence is not a cause. Copy that says
    /// "usually traces to" throws that away in four words.
    ///
    /// Each entry here was a real string in `RuleBasedInsightEngine` or
    /// `WeeklyReport`. Kept as a list rather than deleted with the strings so
    /// they cannot come back, and so the model-backed engines are held to the
    /// same standard as the rule-based one.
    static let causalOverclaimTerms = [
        "fighting something off",
        "traces to",
        "first thing to suffer",
        "ready to train",
        "sleep is the lever",
        "stayed in gear",
        "caused by",
        "this is why",
        "which is why you",
    ]

    static func containsBannedLanguage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return bannedTerms.contains { lowered.contains($0) }
    }

    /// Whether `text` asserts a cause or a verdict Zoon cannot support.
    static func overclaimsCausation(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return causalOverclaimTerms.contains { lowered.contains($0) }
    }

    /// The full check applied to on-device model output.
    ///
    /// Causal overclaiming is included, so a generation that asserts a
    /// mechanism is refused the same way one that names a condition is. That
    /// makes the guard stricter and will occasionally reject an otherwise
    /// fine answer -- an acceptable trade, since both callers fail closed
    /// (`FoundationModelInsightEngine` falls back to the rule engine,
    /// `CoachChat` shows a plain refusal) rather than showing raw output.
    static func rejects(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return containsBannedLanguage(text)
            || overclaimsCausation(text)
            || unsafeGuidanceTerms.contains { lowered.contains($0) }
    }
}
