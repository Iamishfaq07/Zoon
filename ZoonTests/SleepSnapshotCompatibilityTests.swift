import XCTest

/// The app-to-widget contract, which is a *versioning* contract.
///
/// The app and its extensions are separate processes updated together, but a
/// snapshot written before an app update is read after it. Every field added
/// to `SleepSnapshot` after the first release is therefore a `var` with a
/// default, so an older payload still decodes. Get that wrong and the failure
/// isn't a crash in a code path someone is watching -- it's every widget on
/// the home screen going blank, silently, for anyone who hadn't relaunched
/// the app.
///
/// Fourteen fields now carry that defaulting and none of them was covered.
/// The test that matters is the one below: a payload holding *only* the
/// original required fields must still decode.
final class SleepSnapshotCompatibilityTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        // Matches SnapshotStore.read().
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Exactly the non-defaulted (`let`) fields -- what a build predating
    /// every later addition would have written.
    private let legacyPayload = """
    {
      "date": "2026-08-15T00:00:00Z",
      "score": 81,
      "scoreBand": "Good",
      "timeAsleepMinutes": 452,
      "sleepDebtMinutes": 95,
      "goalMinutes": 480,
      "insightSummary": "A solid night.",
      "generatedAt": "2026-08-15T07:30:00Z"
    }
    """

    func testLegacyPayloadStillDecodes() throws {
        let data = Data(legacyPayload.utf8)
        let snapshot = try decoder().decode(SleepSnapshot.self, from: data)

        XCTAssertEqual(snapshot.score, 81)
        XCTAssertEqual(snapshot.scoreBand, "Good")
        XCTAssertEqual(snapshot.insightSummary, "A solid night.")
    }

    /// Each later addition must fall back to its documented default rather
    /// than failing the decode.
    func testLegacyPayloadFallsBackToDefaults() throws {
        let snapshot = try decoder().decode(SleepSnapshot.self, from: Data(legacyPayload.utf8))

        XCTAssertEqual(snapshot.recoveryPercent, 0)
        XCTAssertEqual(snapshot.bodyBattery, 0)
        XCTAssertEqual(snapshot.sleepIntelligencePercent, 0)
        // The Watch and widget both treat an empty band as "nothing to show
        // yet" rather than a real zero -- see SleepSnapshot's doc comment.
        XCTAssertEqual(snapshot.sleepIntelligenceBand, "")
        XCTAssertEqual(snapshot.badgeSymbol, "hexagon.fill")
        XCTAssertEqual(snapshot.badgesUnlocked, 0)
        XCTAssertEqual(snapshot.bodySignalsLabel, "Nothing unusual")
        XCTAssertFalse(snapshot.isMock)
    }

    /// The realistic upgrade path: a payload from an *intermediate* build,
    /// carrying some later fields but not the newest ones. Guards the case
    /// where someone adds a field and forgets its `decodeIfPresent` line.
    func testIntermediatePayloadDecodesWithPartialFields() throws {
        let payload = """
        {
          "date": "2026-08-15T00:00:00Z",
          "score": 81,
          "scoreBand": "Good",
          "timeAsleepMinutes": 452,
          "sleepDebtMinutes": 95,
          "goalMinutes": 480,
          "insightSummary": "A solid night.",
          "generatedAt": "2026-08-15T07:30:00Z",
          "recoveryPercent": 68,
          "bodyBattery": 74
        }
        """

        let snapshot = try decoder().decode(SleepSnapshot.self, from: Data(payload.utf8))

        XCTAssertEqual(snapshot.recoveryPercent, 68)
        XCTAssertEqual(snapshot.bodyBattery, 74)
        // Newer than that build: still defaults.
        XCTAssertEqual(snapshot.bodySignalsLabel, "Nothing unusual")
        XCTAssertEqual(snapshot.badgeSymbol, "hexagon.fill")
    }

    func testRoundTripPreservesLaterFields() throws {
        var original = try decoder().decode(SleepSnapshot.self, from: Data(legacyPayload.utf8))
        original.recoveryPercent = 72
        original.bodySignalsLabel = "Several signals moving"
        original.badgeTier = 3

        let restored = try decoder().decode(
            SleepSnapshot.self, from: encoder().encode(original)
        )

        XCTAssertEqual(restored.recoveryPercent, 72)
        XCTAssertEqual(restored.bodySignalsLabel, "Several signals moving")
        XCTAssertEqual(restored.badgeTier, 3)
        XCTAssertEqual(restored, original)
    }

    // MARK: - balanceLabel

    /// User-facing copy with three branches, shown on the widget and the
    /// Watch. Uses a real minus sign (U+2212), not a hyphen.

    func testBalanceLabelReadsEvenBelowTheThreshold() {
        XCTAssertEqual(snapshot(debtMinutes: 0).balanceLabel, "Even")
        XCTAssertEqual(snapshot(debtMinutes: 14).balanceLabel, "Even")
    }

    func testBalanceLabelUsesOneDecimalUnderTenHours() {
        XCTAssertEqual(snapshot(debtMinutes: 90).balanceLabel, "−1.5h")
    }

    func testBalanceLabelDropsTheDecimalAtTenHoursAndAbove() {
        // Past ten hours the tenth of an hour is noise, and the extra glyph
        // costs width the widget doesn't have.
        XCTAssertEqual(snapshot(debtMinutes: 660).balanceLabel, "−11h")
    }

    func testBalanceLabelNeverImpliesBankedSurplus() {
        // Zero debt reads as "even", never as a positive balance -- you
        // cannot bank surplus sleep.
        XCTAssertFalse(snapshot(debtMinutes: 0).balanceLabel.contains("+"))
    }

    private func snapshot(debtMinutes: Double) -> SleepSnapshot {
        SleepSnapshot(
            date: .now,
            score: 80,
            scoreBand: "Good",
            timeAsleepMinutes: 450,
            sleepDebtMinutes: debtMinutes,
            goalMinutes: 480,
            insightSummary: "",
            generatedAt: .now
        )
    }
}
