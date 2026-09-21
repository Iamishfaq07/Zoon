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
