import XCTest
@testable import Zoon

final class ChartRequestTests: XCTestCase {
    func testParsesMetricAndRange() {
        XCTAssertEqual(ChartRequestParser.parse("show HRV last 90 days weekly"), ChartRequest(metric: .hrv, days: 90, groupedWeekly: true))
        XCTAssertEqual(ChartRequestParser.parse("sleep duration for 7 days")?.metric, .sleepDuration)
    }
    func testUnknownPromptIsRejected() { XCTAssertNil(ChartRequestParser.parse("what caused my bad night")) }
}
