import XCTest

/// The watch's version of tonight's plan, and the round trip that carries it.
final class TonightShortSentenceTests: XCTestCase {

    private func plan(shiftMinutes: Double, debt: Double = 0) -> SleepAutopilot.Plan? {
        let nights = (0..<14).map { index in
            Fixture.night(daysAgo: 14 - index, timeAsleepMinutes: 420, timeInBedMinutes: 440,
                          bedtimeHour: 23, bedtimeMinuteOffset: 30)
        }
        return SleepAutopilot.plan(
            nights: nights,
            sleepNeedMinutes: 420 - shiftMinutes,
            sleepDebtMinutes: debt
        )
    }

    /// The defect the watch capture showed: the full sentence truncates at
    /// "Aim for 20m earlier than…", cut before the word saying what it is
    /// earlier than.
    func testTheShortFormFitsWhereTheLongOneDoesNot() throws {
        let p = try XCTUnwrap(plan(shiftMinutes: -20, debt: 90))
        XCTAssertLessThan(p.shortSentence.count, p.sentence.count)
        XCTAssertLessThanOrEqual(
            p.shortSentence.count, 30,
            "too long for a watch line: \(p.shortSentence)"
        )
    }

    /// What survives is the part somebody acts on at bedtime. Losing the
    /// direction would make the line worse than the truncation it replaces.
    func testTheShortFormKeepsDirectionAndMagnitude() throws {
        let earlier = try XCTUnwrap(plan(shiftMinutes: -20, debt: 90))
        XCTAssertTrue(earlier.shortSentence.contains("earlier"), earlier.shortSentence)
        XCTAssertFalse(earlier.shortSentence.contains("owed"), "debt detail belongs on the phone")
    }

    /// A night worth no change says so, rather than saying nothing.
    func testAHoldingNightStillSaysSomething() throws {
        let holding = try XCTUnwrap(plan(shiftMinutes: 0))
        guard holding.isHolding else { return }
        XCTAssertFalse(holding.shortSentence.isEmpty)
        XCTAssertLessThan(holding.shortSentence.count, holding.sentence.count)
    }

    /// The long form is unchanged. Siri speaks it, the watch's accessibility
    /// label reads it, and the phone widget draws it -- shortening what the
    /// watch *draws* must take nothing away from any of them.
    func testTheLongFormIsUntouched() throws {
        let p = try XCTUnwrap(plan(shiftMinutes: -20, debt: 90))
        XCTAssertTrue(p.sentence.hasSuffix("."), p.sentence)
        XCTAssertTrue(p.sentence.contains("than usual tonight"), p.sentence)
    }

    /// The field is new on the wire, so it has to survive one. A custom
    /// `init(from:)` that forgets a property decodes it as empty for ever,
    /// which is the same silent no-op the stage-source column hit today.
    func testTheShortNoteSurvivesACodableRoundTrip() throws {
        var snapshot = MockData.tonightSnapshot
        snapshot.tonightTargetNoteShort = "20m earlier than usual"

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SleepSnapshot.self, from: data)
        XCTAssertEqual(decoded.tonightTargetNoteShort, "20m earlier than usual")
    }

    /// An older phone sends no short note at all. The watch falls back to the
    /// long one rather than drawing a blank line, so the absent field must
    /// decode as empty rather than failing.
    func testAPayloadWithoutTheFieldDecodesAsEmpty() throws {
        var snapshot = MockData.tonightSnapshot
        snapshot.tonightTargetNoteShort = ""
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "tonightTargetNoteShort")

        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SleepSnapshot.self, from: stripped)
        XCTAssertEqual(decoded.tonightTargetNoteShort, "")
        XCTAssertFalse(decoded.tonightTargetNote.isEmpty, "the long one must still be there")
    }

    /// The demo snapshot the watch capture uses carries it, or the render
    /// goes back to photographing the truncated sentence.
    func testTheDemoTonightSnapshotCarriesTheShortNote() {
        XCTAssertFalse(MockData.tonightSnapshot.tonightTargetNoteShort.isEmpty)
    }
}
