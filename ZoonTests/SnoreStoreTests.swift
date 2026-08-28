import XCTest

/// Covers `SnoreStore`'s move onto night identity, and — more importantly —
/// that the move did not strand the summaries already on people's phones.
@MainActor
final class SnoreStoreTests: XCTestCase {

    /// Mirrors `SnoreStore.key`, which is private. Duplicated deliberately:
    /// a test that seeds legacy data has to write the same literal an older
    /// build wrote, and reading it from the store would make the test pass
    /// even if the key changed underneath existing users.
    private let storageKey = "zoon.snore.nights"

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.zoon.sleep.tests.snore.\(UUID().uuidString)")!
    }

    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, zone: String = "UTC") -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    /// Anchored to local noon in whatever zone the test host runs in.
    ///
    /// The keyless fallback path compares days in `Calendar.current`, so any
    /// fixture exercising it has to be built in that same calendar — a fixed
    /// UTC hour would straddle local midnight on some runners and flake.
    private func localNoon(plusHours hours: Double = 0) -> Date {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        return noon.addingTimeInterval(hours * 3600)
    }

    private func summary(
        date: Date,
        monitored: Double = 480,
        snore: Double = 30,
        nightKey: String? = nil,
        zone: String? = nil
    ) -> SnoreStore.NightSummary {
        SnoreStore.NightSummary(
            date: date,
            monitoredMinutes: monitored,
            snoreMinutes: snore,
            nightKey: nightKey,
            timezoneIdentifier: zone
        )
    }

    // MARK: - Migration

    /// The load-bearing compatibility case: a summary written by a build that
    /// had no concept of `nightKey` must still decode, not vanish. Snore
    /// history is capped at 30 nights and never re-derived from anywhere, so
    /// a decode failure here is permanent data loss.
    func testSummaryStoredBeforeNightKeysExistedStillDecodes() throws {
        let defaults = makeDefaults()
        let recorded = instant(2026, 8, 20, 0, 0)
        // Exactly the shape an older build produced: three keys, no identity.
        // `JSONEncoder`'s default date strategy is seconds since the
        // reference date, so the literal has to match that, not epoch.
        let legacy = """
        [{"date":\(recorded.timeIntervalSinceReferenceDate),\
        "monitoredMinutes":420,"snoreMinutes":18}]
        """
        defaults.set(Data(legacy.utf8), forKey: storageKey)

        let store = SnoreStore(defaults: defaults)

        XCTAssertEqual(store.nights.count, 1)
        let loaded = try XCTUnwrap(store.nights.first)
        XCTAssertEqual(loaded.date, recorded)
        XCTAssertEqual(loaded.monitoredMinutes, 420)
        XCTAssertEqual(loaded.snoreMinutes, 18)
        XCTAssertNil(loaded.nightKey, "A pre-migration row must not be given an invented key.")
        XCTAssertNil(loaded.timezoneIdentifier)
    }

    /// A legacy row has no key, so it must keep being matched the way it
    /// always was — by calendar day. Otherwise re-recording a night that
    /// already has a keyless row would duplicate it rather than replace it.
    func testLegacyRowWithoutAKeyIsStillReplacedBySameDayRecording() {
        let store = SnoreStore(defaults: makeDefaults())
        let morning = localNoon()

        store.record(summary(date: morning, snore: 10))
        store.record(summary(date: morning.addingTimeInterval(3 * 3600), snore: 25))

        XCTAssertEqual(store.nights.count, 1, "Same calendar day, neither row keyed — should replace.")
        XCTAssertEqual(store.nights.first?.snoreMinutes, 25)
    }

    // MARK: - Night-key matching

    func testSameNightKeyReplacesRatherThanDuplicating() {
        let store = SnoreStore(defaults: makeDefaults())
        let key = "2026-08-20@Asia/Tokyo"

        store.record(summary(date: instant(2026, 8, 20, 6, 0), snore: 10, nightKey: key, zone: "Asia/Tokyo"))
        store.record(summary(date: instant(2026, 8, 20, 7, 0), snore: 42, nightKey: key, zone: "Asia/Tokyo"))

        XCTAssertEqual(store.nights.count, 1)
        XCTAssertEqual(store.nights.first?.snoreMinutes, 42)
    }

    /// The travel case, and the reason this change exists. Two genuinely
    /// different nights can land on the same calendar day once the device
    /// moves. Matching on day alone silently discarded one of them; matching
    /// on the recorded night key keeps both.
    func testTwoNightsWithDifferentKeysBothSurviveTheSameCalendarDay() {
        let store = SnoreStore(defaults: makeDefaults())
        let sameDay = instant(2026, 8, 20, 6, 0)

        store.record(summary(
            date: sameDay, snore: 12,
            nightKey: "2026-08-20@Asia/Tokyo", zone: "Asia/Tokyo"
        ))
        store.record(summary(
            date: sameDay.addingTimeInterval(2 * 3600), snore: 31,
            nightKey: "2026-08-20@Asia/Kolkata", zone: "Asia/Kolkata"
        ))

        XCTAssertEqual(store.nights.count, 2)
        XCTAssertEqual(
            Set(store.nights.compactMap(\.nightKey)),
            ["2026-08-20@Asia/Tokyo", "2026-08-20@Asia/Kolkata"]
        )
    }

    /// Identity should follow the key, not the instant, so a row keeps one
    /// `id` for SwiftUI even as the device's zone changes around it.
    func testIdentityPrefersTheNightKey() {
        let keyed = summary(date: instant(2026, 8, 20, 6, 0), nightKey: "2026-08-20@UTC", zone: "UTC")
        let legacy = summary(date: instant(2026, 8, 20, 6, 0))

        XCTAssertEqual(keyed.id, "2026-08-20@UTC")
        XCTAssertNotEqual(legacy.id, keyed.id, "A keyless row must not collide with a keyed one.")
    }

    // MARK: - Import

    func testImportSkipsANightAlreadyStored() {
        let store = SnoreStore(defaults: makeDefaults())
        let key = "2026-08-20@UTC"
        store.record(summary(date: instant(2026, 8, 20, 6, 0), snore: 10, nightKey: key, zone: "UTC"))

        let adopted = store.importSummaries([
            summary(date: instant(2026, 8, 20, 6, 30), snore: 99, nightKey: key, zone: "UTC")
        ])

        XCTAssertEqual(adopted, 0)
        XCTAssertEqual(store.nights.count, 1)
        XCTAssertEqual(store.nights.first?.snoreMinutes, 10, "Import must not overwrite newer local data.")
    }

    func testImportAdoptsANightNotAlreadyStored() {
        let store = SnoreStore(defaults: makeDefaults())
        store.record(summary(date: instant(2026, 8, 20, 6, 0), nightKey: "2026-08-20@UTC", zone: "UTC"))

        let adopted = store.importSummaries([
            summary(date: instant(2026, 8, 21, 6, 0), snore: 44, nightKey: "2026-08-21@UTC", zone: "UTC")
        ])

        XCTAssertEqual(adopted, 1)
        XCTAssertEqual(store.nights.count, 2)
    }

    /// Restoring a backup taken before night keys existed must still
    /// de-duplicate against what the device already has, or every restore
    /// doubles the user's snore history.
    func testImportOfKeylessBackupStillDeduplicatesByDay() {
        let store = SnoreStore(defaults: makeDefaults())
        store.record(summary(date: localNoon(), snore: 10))

        let adopted = store.importSummaries([
            summary(date: localNoon(plusHours: 3), snore: 99)
        ])

        XCTAssertEqual(adopted, 0)
        XCTAssertEqual(store.nights.count, 1)
    }
}
