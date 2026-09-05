import XCTest

/// The snapshot is the only thing the phone tells the Watch and the widgets.
/// If a field does not survive the round trip, the feature that reads it is
/// dead on every surface except the phone -- and dead quietly, because every
/// field falls back to a default that reads as "nothing to show yet".
///
/// That is not hypothetical. `tonightTargetLabel`, `tonightTargetNote`,
/// `tomorrowRangeLabel`, `isTonightTargetHolding`, `headlineFindingText` and
/// `headlineFindingStrength` were all encoded and none were decoded, so the
/// Tonight page, the Tonight widget, the Tonight complication and the watch
/// headline finding had never once displayed real data.
///
/// ## Why these two tests are built the way they are
///
/// `encode(to:)` is synthesised and `init(from:)` is hand-written. That
/// asymmetry is the whole hazard: adding a stored property silently extends
/// the encoder and silently does *not* extend the decoder.
///
/// So neither test enumerates field names. Between them they fail on a field
/// nobody has heard of yet:
///
/// - `testFixtureLeavesNoPropertyAtItsDefault` reflects over the fixture and
///   fails naming any property still at its default, which is what happens
///   when someone adds a property and forgets the fixture.
/// - `testEveryEncodedFieldSurvivesTheRoundTrip` compares encoded JSON before
///   and after a decode, so a property the decoder skips comes back as its
///   default and the two payloads stop matching.
final class SleepSnapshotSerializationTests: XCTestCase {

    /// Every stored property set to something no default could be.
    private func fullyPopulated() -> SleepSnapshot {
        var snapshot = SleepSnapshot(
            features: Fixture.night(daysAgo: 1, timeAsleepMinutes: 431),
            score: SleepScore.compute(for: Fixture.night(daysAgo: 1), goalMinutes: 462),
            insight: SleepInsight(
                summary: "A distinctive summary",
                likelyCause: "cause",
                actionableTip: "tip",
                confidence: .medium
            ),
            goalMinutes: 462
        )
        snapshot.recoveryPercent = 63
        snapshot.bodyBattery = 71
        snapshot.strain = 12.5
        snapshot.sleepPerformance = 88.5
        snapshot.sleepIntelligencePercent = 79
        snapshot.sleepIntelligenceBand = "Distinctive band"
        snapshot.isMock = true
        snapshot.badgeTitle = "Distinctive badge"
        snapshot.badgeSymbol = "star.circle.fill"
        snapshot.badgeTier = 3
        snapshot.badgesUnlocked = 7
        snapshot.badgesTotal = 19
        snapshot.nextBadgeTitle = "Distinctive next badge"
        snapshot.nextBadgeProgress = 0.42
        snapshot.bodySignalsLabel = "Distinctive signals"
        snapshot.isShiftWorkModeEnabled = true
        snapshot.tonightTargetLabel = "10:45 PM - 6:30 AM"
        snapshot.tonightTargetNote = "Aim for 20m earlier than usual tonight."
        snapshot.tomorrowRangeLabel = "Duration: 6h 20m to 8h 05m"
        snapshot.isTonightTargetHolding = true
        snapshot.headlineFindingText = "Late caffeine goes with shorter sleep."
        snapshot.headlineFindingStrength = "Association"
        return snapshot
    }

    /// A snapshot built the plain way, for comparison. Everything optional is
    /// at its declared default here.
    private func atDefaults() -> SleepSnapshot {
        SleepSnapshot(
            features: Fixture.night(daysAgo: 1, timeAsleepMinutes: 431),
            score: SleepScore.compute(for: Fixture.night(daysAgo: 1), goalMinutes: 462),
            insight: SleepInsight(
                summary: "A distinctive summary",
                likelyCause: "cause",
                actionableTip: "tip",
                confidence: .medium
            ),
            goalMinutes: 462
        )
    }

    /// Guards the fixture, not the decoder.
    ///
    /// A property added to `SleepSnapshot` and not added to `fullyPopulated()`
    /// would sit at its default, which would make the round-trip test below
    /// pass for the wrong reason: a field the decoder skips still "matches" if
    /// the value it skipped happened to be the default anyway. This fails
    /// first, and names the property.
    func testFixtureLeavesNoPropertyAtItsDefault() {
        let populated = Mirror(reflecting: fullyPopulated())
        let defaults = Mirror(reflecting: atDefaults())

        // Compared as strings so this needs no per-type knowledge and keeps
        // working for whatever type is added next. Crude, and sufficient:
        // every fixture value above is chosen to be unmistakable.
        var defaultsByLabel: [String: String] = [:]
        for child in defaults.children {
            guard let label = child.label else { continue }
            defaultsByLabel[label] = String(describing: child.value)
        }

        for child in populated.children {
            guard let label = child.label,
                  let defaultValue = defaultsByLabel[label]
            else { continue }
            // These four come from the init and cannot be at a "default".
            guard !["date", "generatedAt", "score", "scoreBand"].contains(label) else { continue }
            XCTAssertNotEqual(
                String(describing: child.value), defaultValue,
                "\(label) is still at its default -- add it to fullyPopulated() "
                    + "so the round-trip test can actually see it"
            )
        }
    }

    /// The decoder test. Fails for any encoded field it does not read back.
    func testEveryEncodedFieldSurvivesTheRoundTrip() throws {
        let encoder = JSONEncoder()
        let original = fullyPopulated()

        let firstPass = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SleepSnapshot.self, from: firstPass)
        let secondPass = try encoder.encode(decoded)

        let before = try XCTUnwrap(
            JSONSerialization.jsonObject(with: firstPass) as? [String: Any]
        )
        let after = try XCTUnwrap(
            JSONSerialization.jsonObject(with: secondPass) as? [String: Any]
        )

        // Reported per key rather than as one opaque inequality, so a failure
        // names the field that was dropped instead of printing two payloads.
        for (key, value) in before {
            let round = after[key]
            XCTAssertEqual(
                String(describing: value), String(describing: round ?? "<missing>"),
                "\(key) did not survive decoding -- it is encoded but "
                    + "init(from:) never reads it"
            )
        }
        XCTAssertEqual(before.count, after.count)
    }

    /// The specific regression, stated in the terms the bug had.
    func testTonightAndHeadlineFieldsReachTheWatch() throws {
        let original = fullyPopulated()
        let decoded = try JSONDecoder().decode(
            SleepSnapshot.self, from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.tonightTargetLabel, original.tonightTargetLabel)
        XCTAssertEqual(decoded.tonightTargetNote, original.tonightTargetNote)
        XCTAssertEqual(decoded.tomorrowRangeLabel, original.tomorrowRangeLabel)
        XCTAssertEqual(decoded.isTonightTargetHolding, original.isTonightTargetHolding)
        XCTAssertEqual(decoded.headlineFindingText, original.headlineFindingText)
        XCTAssertEqual(decoded.headlineFindingStrength, original.headlineFindingStrength)
    }

    /// Backward compatibility: a payload written before any of these fields
    /// existed must still decode, at defaults rather than by throwing.
    func testAnOlderPayloadStillDecodes() throws {
        let json = """
        {
          "date": 760000000,
          "score": 74,
          "scoreBand": "Good",
          "timeAsleepMinutes": 431,
          "sleepDebtMinutes": 62,
          "goalMinutes": 462,
          "insightSummary": "An older summary",
          "generatedAt": 760000100
        }
        """
        let decoded = try JSONDecoder().decode(
            SleepSnapshot.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.score, 74)
        XCTAssertEqual(decoded.tonightTargetLabel, "")
        XCTAssertEqual(decoded.headlineFindingText, "")
        XCTAssertEqual(decoded.badgeSymbol, "hexagon.fill")
        XCTAssertEqual(decoded.bodySignalsLabel, "Nothing unusual")
    }
}
