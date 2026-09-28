import XCTest
import SwiftData

/// `SleepHistoryStore.needHistory` is the one history a learned sleep need is
/// computed from -- both the need Today shows and the need frozen onto each
/// night at ingest, which the shortfall ledger charges against.
///
/// The ingest copy used to be learned from the raw rows. They carry no debt,
/// so a ten-hour weekend slept after a week of six-hour nights looked like a
/// free choice rather than a repayment, and the frozen need came out hours
/// above the one on screen: someone sleeping their displayed need every
/// night still built a shortfall against a number they never saw.
@MainActor
final class SleepNeedHistoryTests: XCTestCase {

    /// Held for the lifetime of the test; see SleepHistoryStoreIntegrationTests.
    private var container: ModelContainer?
    private let goal = 480.0

    private func makeStore() throws -> SleepHistoryStore {
        let container = try ModelContainer(
            for: SleepNightRecord.self, SleepEpisodeRecord.self, EvidenceRevisionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let store = SleepHistoryStore(context: container.mainContext)
        store.restoredNightDefaults = UserDefaults(suiteName: "zoon.tests.need-history.\(UUID().uuidString)")!
        return store
    }

    /// Six-hour weeknights, ten-hour weekends, for `days` nights.
    @discardableResult
    private func seedWeeks(_ store: SleepHistoryStore, days: Int = 60) -> [SleepNightFeatures] {
        var seeded: [SleepNightFeatures] = []
        for daysAgo in stride(from: days, through: 1, by: -1) {
            let probe = Fixture.night(daysAgo: daysAgo)
            let weekday = Calendar.current.component(.weekday, from: probe.date)
            let weekend = weekday == 1 || weekday == 7
            let night = Fixture.night(
                daysAgo: daysAgo,
                timeAsleepMinutes: weekend ? 600 : 360,
                timeInBedMinutes: weekend ? 630 : 400,
                sleepDebtMinutes: nil
            )
            _ = store.upsert(night, nightKey: night.nightKey)
            seeded.append(night)
        }
        return seeded
    }

    func testNeedHistoryCarriesTheDebtEachNightWasSleptUnder() throws {
        let store = try makeStore()
        seedWeeks(store)

        let history = store.needHistory(goalMinutes: goal, repairs: [])
        let raw = store.allNights().map { $0.features() }

        XCTAssertTrue(history.contains { LearnedSleepNeed.isRepayingDebt($0) },
                      "weekend nights after a short week are repayments")
        XCTAssertFalse(raw.contains { LearnedSleepNeed.isRepayingDebt($0) },
                       "the raw rows have no debt, which was the bug")
    }

    func testRepaymentNightsNoLongerInflateTheLearnedNeed() throws {
        let store = try makeStore()
        seedWeeks(store)

        let fromNeedHistory = LearnedSleepNeed.compute(
            goalMinutes: goal,
            history: store.needHistory(goalMinutes: goal, repairs: [])
        ).minutes
        let fromRawRows = LearnedSleepNeed.compute(
            goalMinutes: goal,
            history: store.allNights().reversed().map { $0.features() }
        ).minutes

        XCTAssertGreaterThan(fromRawRows, fromNeedHistory + 60,
                             "raw rows learn the ten-hour weekends as need")
        XCTAssertLessThan(fromNeedHistory, 540)
    }

    func testExcludedNightsAreLeftOut() throws {
        let store = try makeStore()
        let nights = seedWeeks(store, days: 10)
        let excluded = nights[4].nightKey
        store.excludedNightKeys = [excluded]

        let history = store.needHistory(goalMinutes: goal, repairs: [])

        XCTAssertEqual(history.count, nights.count - 1)
        XCTAssertFalse(history.contains { $0.nightKey == excluded })
    }

    func testBoundaryRepairsAreApplied() throws {
        let store = try makeStore()
        let nights = seedWeeks(store, days: 10)
        let target = nights[6]
        let repair = PersonalSetup.Repair(
            nightKey: target.nightKey,
            reason: "Woke earlier than the watch says",
            excluded: false,
            wakeShiftMinutes: -60
        )

        let history = store.needHistory(goalMinutes: goal, repairs: [repair])
        let repaired = try XCTUnwrap(history.first { $0.nightKey == target.nightKey })

        XCTAssertEqual(
            repaired.wakeTime.timeIntervalSince1970,
            target.wakeTime.addingTimeInterval(-3600).timeIntervalSince1970,
            accuracy: 1
        )
    }
}
