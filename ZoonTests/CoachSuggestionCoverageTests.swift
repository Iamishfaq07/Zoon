import XCTest

final class CoachSuggestionCoverageTests: XCTestCase {

    func testEveryFirstPartySuggestionIsRoutableInRulesMode() {
        for question in CoachSuggestionProvider.allFixtureQuestions {
            XCTAssertNotEqual(
                CoachIntentRouter.classify(question),
                .unknown,
                "suggested question has no Rules-mode answer: \(question)"
            )
        }
    }

    /// Routable is not enough: "Which habits seem to affect my sleep?" was
    /// routable and got last night's duration. Each chip the chat shows must
    /// reach the tool that answers it, and a new chip must say which.
    func testEveryChatChipReachesTheToolThatAnswersIt() {
        let expected: [String: CoachToolCatalog.Kind] = [
            "How did I sleep last night?": .getSleepScore,
            "Am I behind on sleep?": .getShortfall,
            "When should I go to bed tonight?": .getTonight,
            "Why was my HRV lower?": .getHRV,
            "Should I train hard today?": .getTrainingContext,
            "What should I do differently tonight?": .getTonight,
            "How did last night compare with my usual?": .getLastNightSummary,
            "What changed this week?": .getTrendSummary,
            "Is a nap a good idea today?": .getNapAdvice,
            "Which habits seem to affect my sleep?": .getBehaviorEvidence,
            "How much deep sleep did I get?": .getLastNightSummary,
            "How is my recovery?": .getRecovery,
            "Why do I wake up at night?": .getLastNightSummary,
            "How much sleep do I need at my age?": .getForYourAge,
            "Is my resting heart rate normal for my age?": .getForYourAge
        ]
        for chip in Set(CoachSuggestionProvider.chatStarters + CoachSuggestionProvider.chatFollowUps) {
            XCTAssertNotNil(expected[chip], "say which tool answers the new chip: \(chip)")
            XCTAssertEqual(CoachToolCatalog.interpret(chip)?.kind, expected[chip], chip)
        }
    }

    /// The new question phrases must not swallow the writes that share
    /// their words.
    func testQuestionPhrasesDoNotSwallowWrites() {
        XCTAssertEqual(CoachToolCatalog.interpret("I had coffee earlier tonight")?.kind, .logCaffeine)
        XCTAssertEqual(CoachToolCatalog.interpret("I had coffee before bed tonight")?.kind, .logCaffeine)
        XCTAssertEqual(CoachToolCatalog.interpret("Start a 25 minute nap")?.kind, .startNap)
        XCTAssertEqual(CoachToolCatalog.interpret("Take a nap for 20 minutes")?.kind, .startNap)
    }

    /// Asking whether to nap is a question, not a request to start one.
    func testAskingAboutANapDoesNotStartOne() {
        for question in ["Should I take a nap?", "Is a nap worth it today?", "Is it ok to nap now?"] {
            XCTAssertEqual(CoachToolCatalog.interpret(question)?.kind, .getNapAdvice, question)
        }
    }

    func testFocusIsNotTonight() {
        XCTAssertEqual(
            CoachToolCatalog.interpret("What should I focus on?")?.kind,
            .getCurrentPriority
        )
        XCTAssertNotEqual(
            CoachToolCatalog.interpret("What should I focus on?")?.kind,
            .getTonight
        )
    }

    func testTwoCoffeesAtFiveKeepServingsAndAfternoon() throws {
        let call = try XCTUnwrap(CoachToolCatalog.interpret("I had two coffees at 5"))
        XCTAssertEqual(call.kind, .logCaffeine)
        XCTAssertEqual(call.proposedServings, 2)
        XCTAssertEqual(call.proposedMinutes, 17 * 60)
        XCTAssertTrue(call.kind.requiresConfirmation)
    }
}
