import XCTest

final class SleepApneaEventSummaryTests: XCTestCase {

    func testZeroIsAStatementAboutWhatWasWritten() {
        let summary = SleepApneaEventSummary(eventCount: 0, firstEvent: nil, lastEvent: nil)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertTrue(summary.sentence.contains("not about whether breathing"))
    }

    func testACountIsNotADiagnosis() {
        let summary = SleepApneaEventSummary(
            eventCount: 3,
            firstEvent: Date(),
            lastEvent: Date()
        )
        XCTAssertEqual(summary.eventCount, 3)
        XCTAssertTrue(summary.sentence.contains("3"))
        XCTAssertTrue(summary.sentence.contains("clinical surface"))
    }

    func testSingularCopy() {
        let summary = SleepApneaEventSummary(eventCount: 1, firstEvent: Date(), lastEvent: Date())
        XCTAssertTrue(summary.sentence.contains("one"))
        XCTAssertFalse(summary.sentence.contains("1 "))
    }
}
