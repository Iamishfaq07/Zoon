import XCTest

/// Delete Everything cannot be undone by a screen that was open when it ran.
@MainActor
final class DataErasureTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.zoon.sleep.tests.erasure.\(UUID().uuidString)")!
    }

    private func summary(daysAgo: Int, key: String) -> SnoreStore.NightSummary {
        SnoreStore.NightSummary(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            monitoredMinutes: 420, snoreMinutes: 20, nightKey: key, timezoneIdentifier: "UTC"
        )
    }

    /// The Snore Check screen holds its own store. Before the guard, it kept
    /// the erased summaries in memory and wrote every one of them back the
    /// moment the session it was running stopped.
    func testAStoreOpenAcrossAnEraseDoesNotWriteErasedSummariesBack() {
        let defaults = makeDefaults()
        // A centre nobody else observes, so this exercises the generation
        // check alone -- the path for an instance that missed the post.
        let quiet = NotificationCenter()
        let open = SnoreStore(defaults: defaults, center: quiet)
        open.record(summary(daysAgo: 3, key: "2026-09-19"))
        open.record(summary(daysAgo: 2, key: "2026-09-20"))
        XCTAssertEqual(open.nights.count, 2)

        SnoreStore.erasePersistedData(defaults: defaults)
        DataErasure.announce(center: NotificationCenter())

        open.record(summary(daysAgo: 0, key: "2026-09-22"))

        let reread = SnoreStore(defaults: defaults, center: quiet)
        XCTAssertEqual(reread.nights.map(\.nightKey), ["2026-09-22"], "erased summaries came back")
    }

    /// A store that did observe the erase drops what it was showing.
    func testAnObservingStoreForgetsWhatItHeld() {
        let defaults = makeDefaults()
        let center = NotificationCenter()
        let open = SnoreStore(defaults: defaults, center: center)
        open.record(summary(daysAgo: 1, key: "2026-09-21"))

        SnoreStore.erasePersistedData(defaults: defaults)
        DataErasure.announce(center: center)

        let expectation = expectation(description: "reloaded")
        DispatchQueue.main.async {
            XCTAssertTrue(open.nights.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testTheGenerationOnlyMovesForward() {
        let before = DataErasure.generation
        DataErasure.announce(center: NotificationCenter())
        XCTAssertEqual(DataErasure.generation, before + 1)
    }
}
