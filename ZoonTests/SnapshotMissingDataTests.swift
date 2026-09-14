import XCTest

/// Missing is not zero, and missing is not normal.
///
/// These pin the migration contract for every metric a snapshot can carry
/// but an older payload may not.
final class SnapshotMissingDataTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The oldest shape: none of the later metrics present.
    private let ancient = """
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

    func testAncientPayloadClaimsNothing() throws {
        let snapshot = try decoder().decode(SleepSnapshot.self, from: Data(ancient.utf8))

        XCTAssertFalse(snapshot.hasRecovery, "Recovery 0 must not read as a score")
        XCTAssertFalse(snapshot.hasEnergy, "Energy 0 must not read as flat")
        XCTAssertFalse(snapshot.hasLoad, "Load 0.0 must not read as a rest day")
        XCTAssertEqual(snapshot.bodySignalsState, "",
                       "A legacy payload cannot vouch that signals were typical")
    }

    /// What the watch and complications actually render for that payload.
    func testAncientPayloadPresentsAsUnknownNotTypical() throws {
        let snapshot = try decoder().decode(SleepSnapshot.self, from: Data(ancient.utf8))
        let signals = SnapshotBodySignals(snapshot: snapshot)

        XCTAssertEqual(signals.state, .unknown)
        XCTAssertFalse(signals.isReassurance, "This is the false-reassurance bug")
        XCTAssertEqual(signals.shortLabel, "—")
    }

    /// A payload that genuinely carried the values keeps them: the fix must
    /// not blank real data in the name of caution.
    func testPayloadWithValuesKeepsThem() throws {
        let payload = """
        {
          "date": "2026-08-15T00:00:00Z",
          "score": 81, "scoreBand": "Good",
          "timeAsleepMinutes": 452, "sleepDebtMinutes": 95, "goalMinutes": 480,
          "insightSummary": "A solid night.",
          "generatedAt": "2026-08-15T07:30:00Z",
          "recoveryPercent": 68, "bodyBattery": 74, "strain": 9.4,
          "bodySignalsLabel": "Nothing unusual"
        }
        """
        let snapshot = try decoder().decode(SleepSnapshot.self, from: Data(payload.utf8))

        XCTAssertTrue(snapshot.hasRecovery)
        XCTAssertTrue(snapshot.hasEnergy)
        XCTAssertTrue(snapshot.hasLoad)
        XCTAssertEqual(snapshot.bodyBattery, 74)
        XCTAssertEqual(snapshot.strain, 9.4, accuracy: 0.001)
        XCTAssertEqual(
            SnapshotBodySignals(snapshot: snapshot).state, .typical,
            "A phone that wrote this label had actually run the radar"
        )
    }

    /// Each explicit state survives a round trip and presents distinctly.
    func testEveryStatePresentsDistinctly() {
        let cases: [(String, SnapshotBodySignals.State, Bool)] = [
            ("Typical", .typical, true),
            ("Watch", .watch, false),
            ("Notable", .notable, false),
            ("Building", .building, false),
            ("No data", .noData, false),
            ("", .unknown, false)
        ]
        for (raw, expected, reassuring) in cases {
            var snapshot = MockData.snapshot
            snapshot.bodySignalsState = raw
            let signals = SnapshotBodySignals(snapshot: snapshot)
            XCTAssertEqual(signals.state, expected, "state for \(raw)")
            XCTAssertEqual(signals.isReassurance, reassuring,
                           "only Typical may reassure, got \(raw)")
        }
    }
}
