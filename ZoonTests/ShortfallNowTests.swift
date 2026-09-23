import XCTest

/// The shortfall on the wrist is the one on the phone, last night included.
final class ShortfallNowTests: XCTestCase {

    private func snapshot(current: Double?) -> SleepSnapshot {
        SleepSnapshot(
            features: Fixture.night(daysAgo: 0),
            score: SleepScore.compute(for: Fixture.night(daysAgo: 0), goalMinutes: 480),
            insight: SleepInsight(summary: "s", likelyCause: nil, actionableTip: "t", confidence: .medium),
            goalMinutes: 480,
            currentShortfallMinutes: current
        )
    }

    /// Z23: the night's own debt figure is what was carried into it. A
    /// snapshot given the current shortfall shows that instead.
    func testTheCurrentShortfallWins() {
        XCTAssertEqual(snapshot(current: 300).sleepDebtMinutes, 300)
    }

    /// Without one, the older behaviour stands rather than a zero.
    func testWithoutItTheNightsFigureStands() {
        let night = Fixture.night(daysAgo: 0)
        XCTAssertEqual(snapshot(current: nil).sleepDebtMinutes, night.sleepDebtMinutes ?? 0)
    }

    /// The wake line survives the trip to the watch, and an older payload
    /// without it decodes to empty rather than failing.
    func testTheWakeStatusLineRoundTrips() throws {
        var sent = snapshot(current: 60)
        sent.wakeStatusLine = "Wake alarm (alarm): 7:00"
        let data = try JSONEncoder().encode(sent)
        XCTAssertEqual(try JSONDecoder().decode(SleepSnapshot.self, from: data).wakeStatusLine, "Wake alarm (alarm): 7:00")

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "wakeStatusLine")
        let old = try JSONDecoder().decode(SleepSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.wakeStatusLine, "")
    }
}
