import Foundation

/// The questions the Coach must answer the same way every time, before any
/// routing, tool or model sees them.
///
/// Health questions reach the Coach phrased every possible way, and the router
/// behind this is built to find a *tool* in a sentence: "my HRV dropped and I
/// have chest pain" used to be answered with an HRV comparison, and "do I have
/// sleep apnea, my breathing disturbances are high" with a breathing tool,
/// because the tool keyword matched first. A message about self-harm was
/// answered with last night's sleep statistics. None of those may ever depend
/// on which keyword appears first, or on a model honouring its instructions
/// this turn, so they are decided here, deterministically, and first.
///
/// The replies never diagnose, never reassure that something is fine, and
/// always say who can actually help. They are fixed text: no numbers from the
/// person's data appear in them.
enum CoachSafety {

    enum Triage: Equatable, Sendable {
        /// Thoughts of self-harm or suicide.
        case crisis
        /// Symptoms that can be an emergency: chest pain, trouble breathing,
        /// fainting.
        case urgentSymptom
        /// "Do I have …": a question about a medical condition.
        case medicalCondition
        /// How much of a medication or supplement to take.
        case medicationDosing
    }

    static func triage(_ utterance: String) -> Triage? {
        let q = normalized(utterance)
        if crisisPhrases.contains(where: { q.contains($0) }) { return .crisis }
        if urgentSymptomPhrases.contains(where: { q.contains($0) }) { return .urgentSymptom }
        if isDosingQuestion(q) { return .medicationDosing }
        if CoachEvidence.isMedicalQuestion(q) { return .medicalCondition }
        return nil
    }

    static func reply(for triage: Triage) -> String {
        switch triage {
        case .crisis:
            "I'm really sorry you're feeling this way, and I'm glad you said it. I'm not able to help with this, but you don't have to go through it alone. If you might act on these thoughts or you're in danger, call your local emergency number now. You can also reach a crisis line any time; in the US, call or text 988."
        case .urgentSymptom:
            "Chest pain, trouble breathing or fainting can be serious, and Zoon can't assess symptoms. If this is happening now or is severe, call your local emergency number. If it comes and goes at night, talk to a doctor soon rather than waiting."
        case .medicalCondition:
            "Zoon can't tell whether you have a medical condition: a wearable's sleep numbers aren't a clinical test. It can show what was measured, like breathing disturbances Apple recorded or how often you woke. If snoring, pauses in breathing or daytime sleepiness worry you, that's worth raising with a doctor."
        case .medicationDosing:
            "Zoon can't advise on medication, supplements or doses; a pharmacist or doctor can, and they'll know what else you take. What Zoon can do is show how your nights went on the days you logged a sleep aid."
        }
    }

    /// Convenience: the reply for `utterance`, or `nil` when it needs none.
    static func reply(to utterance: String) -> String? {
        triage(utterance).map(reply(for:))
    }

    // MARK: - Lexical

    static let crisisPhrases = [
        "suicid", "kill myself", "end my life", "want to die", "wanna die", "self harm", "self-harm",
        "hurt myself", "harm myself", "don't want to live", "dont want to live", "no reason to live",
        "better off dead", "not want to be alive", "don't want to be alive"
    ]

    static let urgentSymptomPhrases = [
        "chest pain", "chest pains", "pain in my chest", "chest tightness", "tight chest", "chest pressure",
        "heart attack", "can't breathe", "cant breathe", "cannot breathe", "can not breathe",
        "trouble breathing", "difficulty breathing", "hard to breathe", "struggling to breathe",
        "short of breath", "shortness of breath", "fainted", "fainting", "passed out", "seizure"
    ]

    private static let dosingSubjects = [
        "melatonin", "magnesium", "sleeping pill", "sleep pill", "sleep aid", "sleeping aid", "medication",
        "medicine", "supplement", "antihistamine", "benadryl", "diphenhydramine", "zolpidem", "ambien",
        "valerian", "tablet", "pill"
    ]

    private static let dosingCues = ["how much", "how many", "dose", "dosage", "mg", "should i take", "can i take", "safe to take"]

    private static func isDosingQuestion(_ q: String) -> Bool {
        dosingSubjects.contains(where: { q.contains($0) }) && dosingCues.contains(where: { q.contains($0) })
    }

    /// Lowercased, curly apostrophes straightened, so "can’t breathe" typed on
    /// an iPhone keyboard matches.
    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }
}
