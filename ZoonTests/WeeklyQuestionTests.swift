import XCTest

final class WeeklyQuestionTests: XCTestCase {

    func testFallbackWhenNoFindingExists() {
        let question = WeeklyQuestion.make(strongestTag: nil, deltaMinutes: nil)
        XCTAssertTrue(question.question.lowercased().contains("cool room"))
        XCTAssertTrue(question.why.lowercased().contains("duration"))
        XCTAssertNil(question.tagLabel)
    }

    func testNegativeDeltaAsksWhetherTheHabitShortensNights() {
        let question = WeeklyQuestion.make(strongestTag: "Late caffeine", deltaMinutes: -28)
        XCTAssertEqual(question.question, "Does late caffeine still shorten your nights?")
        XCTAssertEqual(question.tagLabel, "Late caffeine")
        XCTAssertTrue(question.why.lowercased().contains("duration"))
    }

    func testPositiveDeltaAsksWhetherTheHabitLengthensNights() {
        let question = WeeklyQuestion.make(strongestTag: "Cool room", deltaMinutes: 22)
        XCTAssertEqual(question.question, "Does cool room still lengthen your nights?")
    }
}
