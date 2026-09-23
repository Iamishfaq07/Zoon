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
}
