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

    static func containsBannedLanguage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return bannedTerms.contains { lowered.contains($0) }
    }

    static func rejects(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return containsBannedLanguage(text)
            || unsafeGuidanceTerms.contains { lowered.contains($0) }
    }
}
