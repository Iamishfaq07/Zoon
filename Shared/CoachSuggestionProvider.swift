import Foundation

enum CoachContextMode: Equatable, Sendable {
    case selectedNight
    case today
    case trend
}

/// Every first-party question the Coach tab (and related surfaces) can
/// offer. Rules mode must be able to answer each one without falling
/// through to `.unknown`.
enum CoachSuggestionProvider: Sendable {

    /// Static fixtures covering every category the Coach tab can emit,
    /// including dynamic templates with a sample behaviour name.
    static let allFixtureQuestions: [String] = [
        "How did I sleep last night?",
        "What happened last night?",
        "How much did I sleep?",
        "Am I behind on sleep?",
        "Why was my HRV low last night?",
        "Why was my HRV higher than usual?",
        "Why did I wake up so much?",
        "Should I train today?",
        "What hurt my sleep last night?",
        "What should I do tonight?",
        "What should I focus on?",
        "What changed this month?",
        "What's my sleep trend?",
        "What's Zoon learning about my sleep so far?",
        "Is late caffeine actually affecting me?",
        "Which of my habits might be affecting my sleep?",
        "How should I catch up on sleep this week?",
        "How should I prepare for tomorrow?",
        "Does a cool room change how long you sleep?",
        "What's my Load?",
        "Is my physiological load high?",
        "What's my Recovery?",
        "How much energy do I have?",
        "Why am I tired?",
        "What stands out about this night, what may have mattered, and how certain are you?",
        "Explain the awakenings and marked events in this night. Separate measurements from possible explanations."
    ]

    static func isRoutable(_ question: String) -> Bool {
        CoachIntentRouter.classify(question) != .unknown
    }
}
