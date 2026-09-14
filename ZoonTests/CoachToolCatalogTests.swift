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

    func testDuplicateCallIsIdempotent() {
        let a = CoachToolCatalog.interpret("What's my recovery")
        let b = CoachToolCatalog.interpret("What's my recovery")
        XCTAssertEqual(a, b)
    }
}
