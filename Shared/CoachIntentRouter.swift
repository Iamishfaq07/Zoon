import Foundation

/// Deterministic conversation router that runs before tools and before
/// any language model. "Hi" is a greeting. It is not a sleep analysis.
enum CoachIntentRouter: Sendable {

    enum Intent: Equatable, Sendable {
        case greeting
        case capabilities
        case thanks
        case farewell
        case cancel
        case tool(CoachToolCatalog.Call)
        case unknown
    }

    static func classify(_ utterance: String) -> Intent {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        let q = trimmed.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
        let words = wordSet(q)

        if isCancel(words, q) { return .cancel }
        if isFarewell(words, q) { return .farewell }
        if isThanks(words) { return .thanks }
        if isCapabilities(words, q) { return .capabilities }

        // "Hi, what's my Recovery?" is a health question with a greeting
        // prefix, not a greeting. Strip once, then route what remains.
        let stripped = strippingLeadingGreeting(q)
        if stripped != q {
            if stripped.isEmpty { return .greeting }
            return classify(stripped)
        }

        if isGreeting(words, q) { return .greeting }

        if let call = CoachToolCatalog.interpret(trimmed) {
            return .tool(call)
        }
        return .unknown
    }

    /// Removes a leading greeting ("hi", "good morning", "hey Zoon") so the
    /// intent after it can still run. A greeting that is the whole message
    /// strips to empty, which `classify` reads as a greeting.
    static func strippingLeadingGreeting(_ q: String) -> String {
        let prefixes = [
            "good morning", "good afternoon", "good evening", "morning,", "hiya", "hello", "howdy",
            "hey", "hi", "yo"
        ]
        for prefix in prefixes where q.hasPrefix(prefix) {
            let rest = q.dropFirst(prefix.count)
            // Whole words only: "hint" is not "hi" and "yoga" is not "yo".
            guard startsWithSeparator(rest) else { continue }
            var remainder = rest.trimmingCharacters(in: greetingSeparators)
            // "Hey Zoon, …" names the app; the name is not the question.
            if remainder == "zoon" { remainder = "" }
            if remainder.hasPrefix("zoon ") || remainder.hasPrefix("zoon,") {
                remainder = String(remainder.dropFirst(4)).trimmingCharacters(in: greetingSeparators)
            }
            return remainder
        }
        return q
    }

    private static let greetingSeparators = CharacterSet(charactersIn: ",!.:;-\u{2014}")
        .union(.whitespacesAndNewlines)

    /// `true` for an empty tail or one that starts with a space or punctuation.
    private static func startsWithSeparator(_ text: Substring) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return true }
        return greetingSeparators.contains(scalar)
    }

    /// A reply to a greeting or small talk: short, natural, and never a sleep
    /// analysis. Takes the utterance and the time so "how are you" is answered
    /// as a question and "good morning" in the morning.
    static func greetingReply(
        to utterance: String = "",
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let q = utterance.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        if smallTalkPhrases.contains(where: { q.contains($0) }) {
            return "I'm good, thanks for asking. How did you sleep? I can go through last night with you, or help you plan tonight."
        }
        switch calendar.component(.hour, from: date) {
        case 5..<12:
            return "Good morning. Want the short version of last night, or is there something specific you're wondering about?"
        case 12..<18:
            return "Hi. Ask me about last night, how today is going, or tonight's plan."
        case 18..<24:
            return "Good evening. I can help you get ready for tonight, or look back at last night."
        default:
            return "Hi. It's late, so I'll keep it quick: tonight's plan, or something to help you wind down?"
        }
    }

    /// "How are you" and friends: small talk that deserves an answer, not a
    /// capabilities list.
    static let smallTalkPhrases = [
        "how are you", "how are u", "how r u", "how's it going", "hows it going", "how are things",
        "how's your day", "what's up", "whats up", "how do you do", "nice to meet you"
    ]

    static func capabilitiesReply() -> String {
        "I can help with last night, Recovery, Energy, Load, tonight's plan, recent trends, logged behaviours, and the one thing worth focusing on. I use Zoon's own numbers — I don't invent them, and I don't diagnose."
    }

    static func thanksReply() -> String {
        "You're welcome. Ask whenever you want to look at last night or tonight's plan."
    }

    static func farewellReply() -> String {
        "Goodnight. I'll be here with last night's numbers when you want them."
    }

    static func cancelReply() -> String {
        "Cancelled. Nothing was changed."
    }

    static func unknownReply() -> String {
        "I can help with last night, Recovery, Energy, Load, tonight's plan, recent trends, and logged behaviours."
    }

    // MARK: - Lexical

    private static func wordSet(_ q: String) -> Set<String> {
        Set(
            q.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private static func isGreeting(_ words: Set<String>, _ q: String) -> Bool {
        guard words.count <= 4 else { return false }
        // "How are you?" is small talk; "how are you calculating my score"
        // (five words) is a question and falls through to the tools.
        if smallTalkPhrases.contains(where: { q.contains($0) }) { return true }
        if q == "morning" || q == "morning!" || q == "evening" { return true }
        return !words.isDisjoint(with: [
            "hi", "hey", "hello", "yo", "sup", "hiya", "howdy"
        ])
    }

    private static func isThanks(_ words: Set<String>) -> Bool {
        guard words.count <= 5 else { return false }
        return words.contains("thanks") || words.contains("thank")
    }

    private static func isFarewell(_ words: Set<String>, _ q: String) -> Bool {
        guard words.count <= 4 else { return false }
        if q.hasPrefix("good night") || q.hasPrefix("night night") { return true }
        return !words.isDisjoint(with: ["bye", "goodbye", "goodnight"])
    }

    private static func isCancel(_ words: Set<String>, _ q: String) -> Bool {
        if words.count <= 3, !words.isDisjoint(with: ["cancel", "stop", "nevermind", "never"]) {
            return true
        }
        return q == "stop" || q == "cancel"
    }

    private static func isCapabilities(_ words: Set<String>, _ q: String) -> Bool {
        if q.contains("what can you do") || q.contains("what do you do") { return true }
        if q.contains("who are you") || q.contains("what are you") { return true }
        if words.count <= 3, words.contains("help") { return true }
        return false
    }
}
