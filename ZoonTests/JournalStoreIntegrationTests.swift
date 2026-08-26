import XCTest
import SwiftData

/// Integration coverage for `JournalStore` against a real, in-memory SwiftData
/// store -- not the pure-value-type logic the rest of `ZoonTests` exercises.
///
/// This is the layer that had no automated coverage at all: `JournalCorrelatorTests`
/// tests the correlation engine over hand-built `Observation` values, and
/// `DataExporterTests` round-trips an `Archive` through `Codable`. Neither ever
/// creates a `JournalEntry` row, so nothing verified that an imported backup
/// actually lands in the store with its fields intact -- including `nightKey`,
/// whose whole purpose is to survive the trip.
///
/// Every test method here must be `async throws` even though nothing awaits:
/// a synchronous test on a `@MainActor` XCTestCase goes through XCTest's
/// non-async invocation path, which never actually enters the main actor,
/// and the first isolated call into `JournalStore` then trips the runtime's
/// executor assertion -- EXC_BREAKPOINT/SIGTRAP, no XCTest failure message,
/// whole process dead. See `SleepHistoryStoreIntegrationTests`' header for
/// the full two-bug history behind that.
@MainActor
final class JournalStoreIntegrationTests: XCTestCase {

    private func makeStore() throws -> JournalStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: JournalEntry.self, configurations: config)
        return JournalStore(context: container.mainContext)
    }

    private func day(_ daysAgo: Int) -> Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        )
    }

    private func record(
        date: Date,
        tags: [String] = [],
        nightKey: String? = nil
    ) -> (date: Date, tags: [String], note: String?, feelingRaw: Int?,
          restedRaw: Int?, energyRaw: Int?, sleepinessRaw: Int?, moodRaw: Int?,
          nightKey: String?) {
        (date: date, tags: tags, note: nil, feelingRaw: nil,
         restedRaw: nil, energyRaw: nil, sleepinessRaw: nil, moodRaw: nil,
         nightKey: nightKey)
    }

    // MARK: - Import

    /// The regression this file exists for. `Archive.JournalRecord` gained a
    /// `nightKey` so a restored entry keeps matching the night it was actually
    /// about; before that, every restored entry fell back to date-based
    /// matching and silently mismatched on a travel day. `DataExporterTests`
    /// proves the field survives `Codable`; only this proves it survives all
    /// the way into a real persisted row.
    func testImportPreservesNightKeyOntoTheCreatedRow() async throws {
        let store = try makeStore()
        let date = day(1)

        let created = store.importEntries([
            record(date: date, tags: ["alcohol"], nightKey: "2024-01-15@America/Los_Angeles")
        ])

        XCTAssertEqual(created, 1)
        let entry = try XCTUnwrap(store.entry(for: date))
        XCTAssertEqual(entry.nightKey, "2024-01-15@America/Los_Angeles")
        XCTAssertEqual(entry.tagIdentifiers, ["alcohol"])
    }

    /// A pre-`nightKey` backup has no key to restore. That must import cleanly
    /// as `nil` rather than being rejected or defaulted to a guessed value --
    /// a wrong key is worse than no key, since `entry(forNightKey:fallbackDate:)`
    /// can still fall back on `date` when it's absent.
    func testImportWithoutNightKeyLeavesItNil() async throws {
        let store = try makeStore()
        let date = day(2)

        store.importEntries([record(date: date, tags: ["caffeineLate"])])

        let entry = try XCTUnwrap(store.entry(for: date))
        XCTAssertNil(entry.nightKey)
        XCTAssertEqual(entry.tagIdentifiers, ["caffeineLate"])
    }

    /// Documented merge rule: "Existing entries win on conflict -- a tag you set
    /// on this device is more trustworthy than one from an older archive."
    func testImportDoesNotOverwriteAnExistingEntry() async throws {
        let store = try makeStore()
        let date = day(3)

        store.toggle(.alcohol, on: date)
        let created = store.importEntries([record(date: date, tags: ["caffeineLate"])])

        XCTAssertEqual(created, 0, "an existing row must not be replaced by the archive's copy")
        let entry = try XCTUnwrap(store.entry(for: date))
        XCTAssertEqual(entry.tagIdentifiers, ["alcohol"])
    }

    // MARK: - nightKey backfill and lookup

    /// `entryOrCreate` backfills a key onto a row that predates the column,
    /// rather than leaving it permanently unmatched.
    func testEntryOrCreateBackfillsNightKeyOntoAKeylessRow() async throws {
        let store = try makeStore()
        let date = day(4)

        store.toggle(.alcohol, on: date)
        XCTAssertNil(store.entry(for: date)?.nightKey)

        store.entryOrCreate(for: date, nightKey: "night-1")

        XCTAssertEqual(store.entry(for: date)?.nightKey, "night-1")
    }

    /// Once a row carries a key, a later call with a *different* key must not
    /// silently re-stamp it -- that would let one night's entry be reassigned
    /// to another night.
    func testEntryOrCreateDoesNotOverwriteAnExistingNightKey() async throws {
        let store = try makeStore()
        let date = day(5)

        store.entryOrCreate(for: date, nightKey: "night-original")
        store.entryOrCreate(for: date, nightKey: "night-different")

        XCTAssertEqual(store.entry(for: date)?.nightKey, "night-original")
    }

    /// The join `SleepDataCoordinator.journalObservations()` relies on: match by
    /// key first, and only fall back to the date when no keyed row exists.
    func testLookupPrefersNightKeyOverTheFallbackDate() async throws {
        let store = try makeStore()
        let keyedDate = day(6)
        let otherDate = day(7)

        store.entryOrCreate(for: keyedDate, nightKey: "night-travel")
        store.toggle(.alcohol, on: otherDate)

        let found = store.entry(forNightKey: "night-travel", fallbackDate: otherDate)
        XCTAssertEqual(found?.date, keyedDate, "the keyed row should win over the fallback date")
    }

    func testLookupFallsBackToDateWhenNoRowCarriesTheKey() async throws {
        let store = try makeStore()
        let date = day(8)

        store.toggle(.alcohol, on: date)

        let found = store.entry(forNightKey: "night-never-stored", fallbackDate: date)
        XCTAssertEqual(found?.date, date)
    }
}
