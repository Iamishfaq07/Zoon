import XCTest

final class TonightDataStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testNoSyncAndNoSourceAreStatedNotHidden() {
        XCTAssertEqual(
            TonightDataStatus.line(lastSync: nil, sourceName: nil, now: now),
            "Health not synced yet · last night's source unknown"
        )
        XCTAssertEqual(
            TonightDataStatus.line(lastSync: nil, sourceName: "  ", now: now),
            "Health not synced yet · last night's source unknown"
        )
    }

    func testAgeIsRoundedDownToTheLargestWholeUnit() {
        func line(_ secondsAgo: TimeInterval) -> String {
            TonightDataStatus.line(lastSync: now.addingTimeInterval(-secondsAgo), sourceName: "Apple Watch", now: now)
        }
        XCTAssertEqual(line(20), "Health synced just now · last night from Apple Watch")
        XCTAssertEqual(line(12 * 60 + 30), "Health synced 12m ago · last night from Apple Watch")
        XCTAssertEqual(line(3 * 3600 + 59 * 60), "Health synced 3h ago · last night from Apple Watch")
        XCTAssertEqual(line(30 * 3600), "Health last synced over a day ago · last night from Apple Watch")
    }

    func testASyncStampInTheFutureReadsAsJustNow() {
        XCTAssertTrue(
            TonightDataStatus.line(lastSync: now.addingTimeInterval(300), sourceName: nil, now: now)
                .hasPrefix("Health synced just now")
        )
    }

    func testStageCoverageSaysWhetherStagesWereMeasured() {
        XCTAssertNil(TonightDataStatus.stageCoverage(stagedMinutes: 0, unstagedMinutes: 0))
        XCTAssertEqual(TonightDataStatus.stageCoverage(stagedMinutes: 0, unstagedMinutes: 420), "duration only, no stages")
        XCTAssertEqual(TonightDataStatus.stageCoverage(stagedMinutes: 420, unstagedMinutes: 0), "staged")
        XCTAssertEqual(TonightDataStatus.stageCoverage(stagedMinutes: 300, unstagedMinutes: 120), "staged for 71% of it")
        // Rounded down, so "staged" is never claimed for a night that was not.
        XCTAssertEqual(TonightDataStatus.stageCoverage(stagedMinutes: 94.9, unstagedMinutes: 5.1), "staged for 94% of it")
    }

    func testCoverageJoinsTheSourceClause() {
        XCTAssertEqual(
            TonightDataStatus.line(lastSync: nil, sourceName: "Oura", now: now, stagedMinutes: 0, unstagedMinutes: 400),
            "Health not synced yet · last night from Oura, duration only, no stages"
        )
    }
}
