import XCTest

final class PersonalSetupTests: XCTestCase {
    func testOvernightPlanUsesCalendarDayAcrossDST() throws {
        let parse = ISO8601DateFormatter()
        let now = parse.date(from: "2026-03-07T15:00:00Z")!
        let plan = PersonalSetup.SleepPlan(name: "Weekend", timeZoneIdentifier: "America/New_York",
            bedtimeMinute: 23 * 60, wakeMinute: 7 * 60, weekdays: [7], firstDate: now)
        let window = try XCTUnwrap(plan.nextWindow(after: now))
        XCTAssertEqual(window.duration, 7 * 3600)
        XCTAssertEqual(window.end, parse.date(from: "2026-03-08T11:00:00Z"))
    }

    func testNightShiftWindowAndDisabledPlan() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-06T07:00:00Z")!
        var plan = PersonalSetup.SleepPlan(name: "After shift", timeZoneIdentifier: "UTC",
            bedtimeMinute: 8 * 60, wakeMinute: 16 * 60, weekdays: Set(1...7), firstDate: now)
        XCTAssertEqual(try XCTUnwrap(plan.nextWindow(after: now)).duration, 8 * 3600)
        plan.enabled = false
        XCTAssertNil(plan.nextWindow(after: now))
    }

    func testPausedRoutineRetainsRemainingTimeAcrossRelaunch() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var setup = PersonalSetup()
        setup.session = .init(startedAt: now, deadline: now.addingTimeInterval(600), pausedSeconds: 420)
        let copy = try JSONDecoder().decode(PersonalSetup.self, from: JSONEncoder().encode(setup))
        XCTAssertEqual(copy.session?.remaining(at: now.addingTimeInterval(5000)), 420)
    }

    func testEncryptedArchiveRejectsWrongPasswordAndTampering() throws {
        let original = Data("private sleep archive".utf8)
        let passphrase = "a long moon phrase 🌙"
        let sealed = try ArchiveCipher.seal(original, passphrase: passphrase)
        XCTAssertEqual(try ArchiveCipher.open(sealed, passphrase: passphrase), original)
        XCTAssertThrowsError(try ArchiveCipher.open(sealed, passphrase: "wrong password"))
        var envelope = try JSONDecoder().decode(ArchiveCipher.Envelope.self, from: sealed)
        var bytes = envelope.sealed
        bytes[bytes.count - 1] ^= 1
        envelope = .init(salt: envelope.salt, rounds: envelope.rounds, sealed: bytes)
        XCTAssertThrowsError(try ArchiveCipher.open(JSONEncoder().encode(envelope), passphrase: passphrase))
        XCTAssertNotEqual(try ArchiveCipher.seal(original, passphrase: passphrase), sealed)
    }

    func testCoachHistoricalEvidenceExcludesFutureNight() {
        let selected = Fixture.night(daysAgo: 4)
        let past = Fixture.night(daysAgo: 5)
        let future = Fixture.night(daysAgo: 1)
        let evidence = CoachEvidence(night: selected, history: [future, past, selected])
        XCTAssertEqual(evidence.history.map(\.date), [past.date])
        XCTAssertEqual(evidence.night.date, selected.date)
        XCTAssertFalse(CoachEvidence.allowsGeneratedProse("Your HRV was 99 ms"))
        XCTAssertNil(evidence.catalog["invented-source"])
    }
}
