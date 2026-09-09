import XCTest

final class CoachEvidenceTests: XCTestCase {

    func testBehindOnSleepUsesDebtNotAGenericDurationLine() {
        let night = Fixture.night(timeAsleepMinutes: 390, sleepDebtMinutes: 90)
        let reply = CoachEvidence(night: night, history: []).reply(to: "Am I behind on sleep?")
        XCTAssertTrue(reply.text.lowercased().contains("yes"))
        XCTAssertTrue(reply.text.contains("1h 30m") || reply.text.contains("90"))
        XCTAssertTrue(reply.text.lowercased().contains("recent nights"))
        XCTAssertFalse(reply.text.lowercased().contains("last night left"))
        XCTAssertNotNil(reply.evidence)
        XCTAssertNotNil(reply.action)
        XCTAssertFalse(DiagnosticLanguageGuard.rejects(reply.text))
    }

    func testCaughtUpNightIsNotBehind() {
        let night = Fixture.night(timeAsleepMinutes: 480, sleepDebtMinutes: 0)
        let reply = CoachEvidence(night: night, history: []).reply(to: "Am I behind on sleep?")
        XCTAssertTrue(reply.text.lowercased().contains("no"))
        XCTAssertFalse(reply.text.lowercased().contains("unpaid"))
    }

    func testHRVComparesAgainstSevenDayAverage() {
        // Fixture copies avgHRV into hrv7DayAvg, so 42 vs 42 is "close to".
        let night = Fixture.night(avgHRV: 42)
        let close = CoachEvidence(night: night, history: []).reply(to: "Why was my HRV low last night?")
        XCTAssertTrue(close.text.contains("42"))
        XCTAssertTrue(close.text.lowercased().contains("close to"))
        XCTAssertEqual(close.evidence, "HRV: 42 ms")
    }

    func testMissingHRVDoesNotInventANumber() {
        let night = Fixture.night(avgHRV: nil)
        let reply = CoachEvidence(night: night, history: []).reply(to: "Why was my HRV low last night?")
        XCTAssertTrue(reply.text.lowercased().contains("wasn't recorded"))
        XCTAssertNil(reply.evidence)
        XCTAssertFalse(reply.text.contains("ms"))
    }

    func testTrainDefersWhenDebtIsHigh() {
        let night = Fixture.night(sleepDebtMinutes: 80, lastWorkoutHoursBeforeBed: 2)
        let reply = CoachEvidence(night: night, history: []).reply(to: "Should I train today?")
        XCTAssertTrue(reply.text.lowercased().contains("lighter"))
        XCTAssertNotNil(reply.action)
    }

    func testWakeCountIsGrounded() {
        let night = Fixture.night(timeAsleepMinutes: 400, timeInBedMinutes: 480, wakeCount: 4)
        let reply = CoachEvidence(night: night, history: []).reply(to: "Why did I wake up so much?")
        XCTAssertTrue(reply.text.contains("4"))
        XCTAssertFalse(DiagnosticLanguageGuard.rejects(reply.text + (reply.action ?? "")))
    }

    func testLocalAnswersMayContainDigitsUnlikeGeneratedProse() {
        XCTAssertFalse(CoachEvidence.allowsGeneratedProse("Your HRV was 42 ms"))
        let reply = CoachEvidence(night: Fixture.night(), history: []).reply(to: "How did I sleep last night?")
        XCTAssertTrue(reply.text.contains("asleep"))
        XCTAssertNotNil(reply.evidence)
    }
}
