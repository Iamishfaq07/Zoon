import XCTest

final class MorningBriefCopyTests: XCTestCase {

    func testATipWithoutNumbersPassesThrough() {
        XCTAssertEqual(
            MorningBriefCopy.body(actionableTip: "Dim the lights an hour before bed."),
            "Dim the lights an hour before bed."
        )
    }

    func testADurationIsStrippedToTheGenericLine() {
        XCTAssertEqual(
            MorningBriefCopy.body(actionableTip: "Make up 1h 30m tonight."),
            MorningBriefCopy.genericBody
        )
        XCTAssertEqual(
            MorningBriefCopy.body(actionableTip: "You're about 90 minutes behind."),
            MorningBriefCopy.genericBody
        )
    }

    func testAClockTimeIsStripped() {
        XCTAssertEqual(
            MorningBriefCopy.body(actionableTip: "Be in bed by 23:40."),
            MorningBriefCopy.genericBody
        )
    }

    func testAPercentOrBpmIsStripped() {
        XCTAssertTrue(MorningBriefCopy.containsMeasurement("Recovery is 62%"))
        XCTAssertTrue(MorningBriefCopy.containsMeasurement("Resting heart rate 58 bpm"))
        XCTAssertFalse(MorningBriefCopy.containsMeasurement("Put the phone in another room."))
    }

    func testEmptyFallsBack() {
        XCTAssertEqual(MorningBriefCopy.body(actionableTip: "  "), MorningBriefCopy.genericBody)
    }
}
