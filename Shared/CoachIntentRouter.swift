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
        let words = wordSet(q)

        if isCancel(words, q) { return .cancel }
        if isFarewell(words) { return .farewell }
        if isThanks(words) { return .thanks }
        if isCapabilities(words, q) { return .capabilities }
        if isGreeting(words) { return .greeting }

        if let call = CoachToolCatalog.interpret(trimmed) {
            return .tool(call)
        }
        return .unknown
    }

    static func greetingReply() -> String {
        "Hi — ask me about last night, Recovery, tonight's plan, or what Zoon has learned from your recent sleep."
    }

    static func capabilitiesReply() -> String {
        "I can help with last night, Recovery, Energy, tonight's plan, recent trends, and logged behaviors. I use Zoon's own numbers — I don't invent them, and I don't diagnose."
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
        "I can help with last night, Recovery, Energy, tonight's plan, recent trends, and logged behaviors."
    }

    // MARK: - Lexical

    private static func wordSet(_ q: String) -> Set<String> {
        Set(
            q.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private static func isGreeting(_ words: Set<String>) -> Bool {
        guard words.count <= 4 else { return false }
        return !words.isDisjoint(with: [
            "hi", "hey", "hello", "yo", "sup", "hiya", "howdy"
        ])
    }

    private static func isThanks(_ words: Set<String>) -> Bool {
        guard words.count <= 5 else { return false }
        return words.contains("thanks") || words.contains("thank")
    }

    private static func isFarewell(_ words: Set<String>) -> Bool {
        guard words.count <= 4 else { return false }
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
