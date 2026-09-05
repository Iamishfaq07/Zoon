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

    /// The decoder test, and it needs no fixture at all.
    ///
    /// Encodes a snapshot, then **perturbs every value in the resulting JSON**
    /// -- numbers shifted, booleans flipped, strings suffixed -- decodes that,
    /// and re-encodes. Any key `init(from:)` ignores comes back carrying the
    /// original value instead of the perturbed one, so the payloads differ and
    /// the test names the key.
    ///
    /// Written this way because the hazard is the property that does not exist
    /// yet. Nothing here enumerates field names, and nothing depends on a
    /// hand-maintained fixture being exhaustive -- an earlier version of this
    /// test did, and it was both weaker and wrong: a skipped field whose value
    /// happened to equal its default would have round-tripped cleanly.
    func testEveryEncodedFieldSurvivesTheRoundTrip() throws {
        let encoder = JSONEncoder()
        let original = try encoder.encode(fullyPopulated())
        let asDictionary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )

        // Perturbed per JSON type.
        //
        // `value as? Bool` is not usable here: JSONSerialization returns
        // NSNumber for both booleans and numbers, and that cast succeeds for
        // any NSNumber equal to 0 or 1 -- so `badgeTier: 0` would be "flipped"
        // to true and then fail to decode as an Int. CFBooleanGetTypeID is the
        // only reliable discriminator.
        var perturbed: [String: Any] = [:]
        for (key, value) in asDictionary {
            if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
                perturbed[key] = !((value as? Bool) ?? false)
            } else if let number = value as? NSNumber {
                // Dates encode as seconds, so they shift with everything else.
                perturbed[key] = number.doubleValue + 7
            } else if let text = value as? String {
                perturbed[key] = text + " (perturbed)"
            } else {
                perturbed[key] = value
            }
        }
        XCTAssertEqual(perturbed.count, asDictionary.count, "perturbation dropped a key")

        let perturbedData = try JSONSerialization.data(withJSONObject: perturbed)
        let decoded = try JSONDecoder().decode(SleepSnapshot.self, from: perturbedData)
        let round = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encoder.encode(decoded)) as? [String: Any]
        )

        for (key, expected) in perturbed {
            let actual = round[key]
            // Compared numerically where both sides are numbers: an Int
            // property re-encodes as 81 while the perturbed value was 81.0,
            // and comparing those as strings would fail for no reason.
            if let lhs = expected as? NSNumber, let rhs = actual as? NSNumber {
                XCTAssertEqual(
                    lhs.doubleValue, rhs.doubleValue, accuracy: 0.0001,
                    "\(key) did not survive decoding -- it is encoded but "
                        + "init(from:) never reads it"
                )
            } else {
                XCTAssertEqual(
                    String(describing: expected),
                    String(describing: actual ?? "<missing>"),
                    "\(key) did not survive decoding -- it is encoded but "
                        + "init(from:) never reads it"
                )
            }
        }
        XCTAssertEqual(round.count, perturbed.count)
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
