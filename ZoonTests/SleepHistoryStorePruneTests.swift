import XCTest
import SwiftData

/// `SleepHistoryStore.prune` is the fix for a real gap: `processSessions`
/// upserts nights a fresh HealthKit fetch produces, but until this existed,
/// nothing ever removed a night whose only sample was deleted or corrected
/// away in the Health app -- the stored record just sat there forever,
/// silently diverging from what Health actually has. These tests exercise
/// that removal path directly against an in-memory SwiftData store.
///
/// Test methods are `async` even though nothing here awaits: `SleepHistoryStore`
/// is `@MainActor`, and an `async` test method is what lets XCTest's runner
/// actually hop onto the main actor before calling into it. A synchronous
/// test method on this same `@MainActor` class crashed the whole test
/// process instead of failing cleanly (verified in CI, not local heuristics)
/// -- consistent with XCTest's non-async invocation path not entering the
/// actor context the compiler assumed it would.
@MainActor
final class SleepHistoryStorePruneTests: XCTestCase {

    private func makeStore() throws -> SleepHistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SleepNightRecord.self, configurations: config)
        return SleepHistoryStore(context: container.mainContext)
    }

    private func insert(_ store: SleepHistoryStore, daysAgo: Int) -> Date {
        let date = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        )
        let features = Fixture.night(daysAgo: daysAgo)
        store.upsert(features)
        return date
    }

    func testNightMissingFromFreshFetchIsRemoved() async throws {
        let store = try makeStore()
        let staleDate = insert(store, daysAgo: 3)

        XCTAssertNotNil(store.night(on: staleDate))

        let window = DateInterval(start: staleDate.addingTimeInterval(-86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNil(store.night(on: staleDate))
    }

    func testNightStillPresentInFreshFetchSurvives() async throws {
        let store = try makeStore()
        let date = insert(store, daysAgo: 2)

        let window = DateInterval(start: date.addingTimeInterval(-86_400), end: .now)
        store.prune(window: window, keeping: [date])

        XCTAssertNotNil(store.night(on: date))
    }

    /// The scoping guarantee: a night outside the re-verified window was
    /// never re-checked against HealthKit, so it must survive even though
    /// it isn't in `keeping` -- otherwise every sync would eventually erase
    /// all history older than the rolling window.
    func testNightOutsideWindowIsNeverTouched() async throws {
        let store = try makeStore()
        let oldDate = insert(store, daysAgo: 400)

        let window = DateInterval(start: .now.addingTimeInterval(-7 * 86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNotNil(store.night(on: oldDate))
    }

    func testPruneOnEmptyKeepingRemovesEverythingInWindow() async throws {
        let store = try makeStore()
        let d1 = insert(store, daysAgo: 1)
        let d2 = insert(store, daysAgo: 2)

        let window = DateInterval(start: d2.addingTimeInterval(-86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNil(store.night(on: d1))
        XCTAssertNil(store.night(on: d2))
    }
}
