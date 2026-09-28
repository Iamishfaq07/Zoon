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

    /// The chat's first questions, on an empty conversation.
    ///
    /// Here rather than in the view so the coverage tests read the chips
    /// people actually tap. They used to check a hand-copied list that had
    /// drifted, and five of the real chips got a generic or wrong answer.
    static let chatStarters: [String] = [
        "How did I sleep last night?",
        "Am I behind on sleep?",
        "When should I go to bed tonight?",
        "Why was my HRV lower?",
        "Should I train hard today?"
    ]

    /// Offered three at a time after each answer.
    static let chatFollowUps: [String] = [
        "What should I do differently tonight?",
        "How did last night compare with my usual?",
        "What changed this week?",
        "Is a nap a good idea today?",
        "Which habits seem to affect my sleep?",
        "How much deep sleep did I get?",
        "Am I behind on sleep?",
        "When should I go to bed tonight?",
        "How is my recovery?",
        "Why do I wake up at night?",
        // Answered from the age range and heart context in the digest.
        "How much sleep do I need at my age?",
        "Is my resting heart rate normal for my age?"
    ]

    /// Every first-party question: the chat's chips and the Coach tab's.
    static var allFixtureQuestions: [String] {
        chatStarters + chatFollowUps + tabFixtureQuestions
    }

    /// Static fixtures covering every category the Coach tab can emit,
    /// including dynamic templates with a sample behaviour name.
    static let tabFixtureQuestions: [String] = [
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
}
