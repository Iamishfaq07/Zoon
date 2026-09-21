import XCTest

final class CoachIntentRouterTests: XCTestCase {

    func testGreetingsAreNotHealthQuestions() {
        for utterance in ["hi", "Hi", "hello", "Hey!", "hi hello"] {
            XCTAssertEqual(CoachIntentRouter.classify(utterance), .greeting, utterance)
            XCTAssertFalse(CoachIntentRouter.greetingReply().lowercased().contains("asleep"))
        }
    }

    func testThanksAndByeStayConversational() {
        XCTAssertEqual(CoachIntentRouter.classify("thanks"), .thanks)
        XCTAssertEqual(CoachIntentRouter.classify("thank you"), .thanks)
        XCTAssertEqual(CoachIntentRouter.classify("bye"), .farewell)
    }

    func testWhoAreYouIsCapabilitiesNotUnknown() {
        XCTAssertEqual(CoachIntentRouter.classify("who are you"), .capabilities)
        XCTAssertEqual(CoachIntentRouter.classify("what can you do"), .capabilities)
        XCTAssertEqual(CoachIntentRouter.classify("help"), .capabilities)
        XCTAssertTrue(CoachIntentRouter.capabilitiesReply().lowercased().contains("last night"))
    }

    func testCancelIsCancel() {
        XCTAssertEqual(CoachIntentRouter.classify("cancel"), .cancel)
        XCTAssertEqual(CoachIntentRouter.classify("stop"), .cancel)
    }

    func testNaturalLanguageSleepQuestionsHitTools() {
        XCTAssertEqual(kind("What happened last night?"), .getSleepScore)
        XCTAssertEqual(kind("How much did I sleep?"), .getSleepScore)
        XCTAssertEqual(kind("How am I doing today?"), .getRecovery)
        XCTAssertEqual(kind("What's my Recovery?"), .getRecovery)
        XCTAssertEqual(kind("How much energy do I have?"), .getEnergy)
        XCTAssertEqual(kind("What should I do tonight?"), .getTonight)
        XCTAssertEqual(kind("When should I sleep?"), .getTonight)
        XCTAssertEqual(kind("Why do I feel tired?"), .getRecovery)
    }

    func testUnknownDoesNotBecomeASleepSummary() {
        XCTAssertEqual(CoachIntentRouter.classify("tell me a joke"), .unknown)
        XCTAssertFalse(CoachIntentRouter.unknownReply().lowercased().contains("asleep"))
    }

    func testAWriteStillConfirms() {
        if case .tool(let call) = CoachIntentRouter.classify("Start a 25 minute nap") {
            XCTAssertEqual(call.kind, .startNap)
            XCTAssertTrue(call.kind.requiresConfirmation)
        } else {
            XCTFail("nap should remain a confirmed write")
        }
    }

    private func kind(_ utterance: String) -> CoachToolCatalog.Kind? {
        if case .tool(let call) = CoachIntentRouter.classify(utterance) {
            return call.kind
        }
        return nil
    }
}
