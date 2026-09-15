import XCTest

final class CoachToolCatalogTests: XCTestCase {

    func testReadOnlySleepQuestionDoesNotRequireConfirmation() {
        let call = CoachToolCatalog.interpret("How did I sleep last night?")
        XCTAssertEqual(call?.kind, .getSleepScore)
        XCTAssertEqual(call?.kind.requiresConfirmation, false)
        XCTAssertNil(call?.confirmationPrompt)
    }

    func testLogCoffeeRequiresConfirmationAndDoesNotInventAScore() {
        let call = CoachToolCatalog.interpret("Log coffee at 5.")
        XCTAssertEqual(call?.kind, .logCaffeine)
        XCTAssertEqual(call?.kind.requiresConfirmation, true)
        XCTAssertTrue(call?.confirmationPrompt?.contains("caffeine") == true)
        XCTAssertEqual(call?.proposedMinutes, 5 * 60)
    }

    func testRejectedOrUnknownUtteranceIsNil() {
        XCTAssertNil(CoachToolCatalog.interpret("Tell me a joke"))
    }

    func testNapParsesDurationAndAsksToConfirm() {
        let call = CoachToolCatalog.interpret("Start a 25 minute nap")
        XCTAssertEqual(call?.kind, .startNap)
        XCTAssertEqual(call?.proposedMinutes, 25)
        XCTAssertTrue(call?.kind.requiresConfirmation == true)
    }

    func testTomorrowOpensThePlannerAfterConfirm() {
        let call = CoachToolCatalog.interpret("Prepare me for my 9 AM meeting tomorrow")
        XCTAssertEqual(call?.kind, .prepareTomorrow)
        XCTAssertEqual(call?.proposedMinutes, 9 * 60)
    }

    /// The nap branch used fixed phrases, and "start a 25 minute nap" contains
    /// none of them -- the duration sits between "start a" and "nap". It
    /// returned nil, so `parseNapMinutes` was never even reached.
    func testNapPhrasingWithTheDurationInTheMiddleStillParses() {
        for utterance in [
            "Start a 25 minute nap",
            "start a 40 min nap",
            "take a nap",
            "set a 20 minute nap"
        ] {
            let call = CoachToolCatalog.interpret(utterance)
            XCTAssertEqual(call?.kind, .startNap, "did not recognise: \(utterance)")
            XCTAssertTrue(call?.kind.requiresConfirmation == true)
        }
    }

    /// "nap" inside another word is not a nap request, and a question about a
    /// past nap is not a request to start one.
    func testNapWordAloneDoesNotStartANap() {
        XCTAssertNil(CoachToolCatalog.interpret("how was my nap"))
        XCTAssertNil(CoachToolCatalog.interpret("tell me about kidnapping"))
    }

    /// The regex always captured the minutes and the parser threw them away,
    /// so the feature's own headline example resolved to the wrong time.
    func testMinutesInASpokenTimeAreKept() {
        let call = CoachToolCatalog.interpret("Prepare me for my 8:30 meeting tomorrow")
        XCTAssertEqual(call?.kind, .prepareTomorrow)
        XCTAssertEqual(call?.proposedMinutes, 8 * 60 + 30)
    }

    func testAfternoonTimesResolveWithMeridiem() {
        let call = CoachToolCatalog.interpret("Log coffee at 3:45 pm")
        XCTAssertEqual(call?.kind, .logCaffeine)
        XCTAssertEqual(call?.proposedMinutes, 15 * 60 + 45)
    }

    /// A bare "tomorrow" used to be matched ahead of every read-only branch,
    /// so a question routed into a confirm-to-write tool.
    func testReadQuestionsAreNotRoutedIntoAWrite() {
        for utterance in ["What's my recovery tomorrow", "How did I sleep, and what about tomorrow"] {
            let call = CoachToolCatalog.interpret(utterance)
            XCTAssertEqual(
                call?.kind.requiresConfirmation, false,
                "a question was routed to a write tool: \(utterance)"
            )
        }
    }

    /// `.getTomorrow` was declared and returned by no branch.
    func testTomorrowPlanCanBeRead() {
        let call = CoachToolCatalog.interpret("What's my tomorrow plan")
        XCTAssertEqual(call?.kind, .getTomorrow)
        XCTAssertEqual(call?.kind.requiresConfirmation, false)
        XCTAssertNil(call?.confirmationPrompt)
    }

    /// Every kind the catalog declares must be reachable from some utterance.
    /// This is the test that would have caught `.getTomorrow` on the way in.
    func testEveryKindIsReachable() {
        let utterances = [
            "How did I sleep last night?", "What's my recovery", "Am I behind on sleep",
            "What's my energy now", "When should I sleep", "What's my tomorrow plan",
            "Log coffee at 5.", "Start a 25 minute nap",
            "Prepare me for my 9 AM meeting tomorrow", "Set my alarm"
        ]
        let reached = Set(utterances.compactMap { CoachToolCatalog.interpret($0)?.kind })
        for kind in [CoachToolCatalog.Kind.getSleepScore, .getRecovery, .getShortfall,
                     .getEnergy, .getTonight, .getTomorrow, .logCaffeine,
                     .startNap, .prepareTomorrow, .setAlarm] {
            XCTAssertTrue(reached.contains(kind), "\(kind.rawValue) is unreachable")
        }
    }

    func testDuplicateCallIsIdempotent() {
        let a = CoachToolCatalog.interpret("What's my recovery")
        let b = CoachToolCatalog.interpret("What's my recovery")
        XCTAssertEqual(a, b)
    }
}
