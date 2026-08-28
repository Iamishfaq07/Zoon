import XCTest

/// Guards `NightKey` — the one place a night's persisted identity is built.
///
/// These are format tests as much as logic tests. `nightKey` values are
/// written into `SleepNightRecord`, `SleepEpisodeRecord`, `JournalEntry`,
/// `BehaviorObservationRecord` and every backup archive, so a change to the
/// string it produces does not fail loudly — it silently detaches nights from
/// the journal entries, behaviour answers and episodes that referenced them.
final class NightIdentityTests: XCTestCase {

    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    /// The exact persisted shape. If this test needs updating, existing user
    /// data is being orphaned — that is the point of asserting the literal.
    func testNightKeyFormatIsStable() {
        let wake = instant(2026, 8, 28, 7, 30, zone: "Asia/Tokyo")
        XCTAssertEqual(
            NightKey.make(wakeInstant: wake, in: TimeZone(identifier: "Asia/Tokyo")!),
            "2026-08-28@Asia/Tokyo"
        )
    }

    /// Single-digit months and days must stay zero-padded, or keys stop
    /// sorting lexicographically and stop matching their older selves.
    func testNightKeyZeroPadsMonthAndDay() {
        let wake = instant(2026, 1, 5, 6, 0, zone: "Asia/Tokyo")
        XCTAssertEqual(
            NightKey.make(wakeInstant: wake, in: TimeZone(identifier: "Asia/Tokyo")!),
            "2026-01-05@Asia/Tokyo"
        )
    }

    /// A trap worth pinning: `TimeZone(identifier: "UTC").identifier` is
    /// `"GMT"` on Apple platforms, so a key built for UTC is stamped `@GMT`.
    /// Harmless — it is stable and round-trips — but anyone reading a raw
    /// persisted key, or writing a fixture, will otherwise expect `@UTC`.
    func testUTCIsNormalisedToGMTInTheKey() {
        let wake = instant(2026, 8, 28, 12, 0, zone: "UTC")
        XCTAssertEqual(
            NightKey.make(wakeInstant: wake, in: TimeZone(identifier: "UTC")!),
            "2026-08-28@GMT"
        )
    }

    /// The property the whole type exists for: the *same instant* belongs to
    /// different local days depending on the zone it is read in. A night is
    /// filed under the zone it was recorded in, so the key must not drift
    /// when the device later travels.
    func testSameInstantYieldsDifferentKeysInDifferentZones() {
        // 22:30 UTC on Aug 27 is already 07:30 on Aug 28 in Tokyo, but
        // still 15:30 on Aug 27 in Los Angeles.
        let wake = instant(2026, 8, 27, 22, 30, zone: "UTC")

        XCTAssertEqual(
            NightKey.make(wakeInstant: wake, in: TimeZone(identifier: "Asia/Tokyo")!),
            "2026-08-28@Asia/Tokyo"
        )
        XCTAssertEqual(
            NightKey.make(wakeInstant: wake, in: TimeZone(identifier: "America/Los_Angeles")!),
            "2026-08-27@America/Los_Angeles"
        )
    }

    /// An unresolvable identifier — a zone renamed or dropped by a later OS,
    /// or a record written before zones were stored — must still produce a
    /// key rather than crash or return empty.
    func testUnresolvableTimeZoneIdentifierFallsBackToCurrent() {
        let wake = instant(2026, 8, 28, 7, 30, zone: "UTC")
        let key = NightKey.make(wakeInstant: wake, timeZoneIdentifier: "Not/AZone")

        XCTAssertEqual(
            key,
            NightKey.make(wakeInstant: wake, in: .current),
            "An unresolvable identifier should behave exactly as the device's current zone."
        )
    }

    /// `SleepNightFeatures.nightKey` used to reimplement the derivation. It
    /// now delegates, and this pins that down — including that it reads the
    /// night's *recorded* zone rather than the device's.
    func testSleepNightFeaturesDelegatesToNightKey() {
        var night = Fixture.night()
        night.timeZoneIdentifier = "Asia/Tokyo"

        XCTAssertEqual(
            night.nightKey,
            NightKey.make(wakeInstant: night.date, in: TimeZone(identifier: "Asia/Tokyo")!)
        )
        XCTAssertTrue(night.nightKey.hasSuffix("@Asia/Tokyo"))
    }
}
