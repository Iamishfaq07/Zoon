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

    // MARK: - Not everything is a question about sleep

    /// The local replies are what every answer falls back to when the model
    /// is unavailable, and the router used to end in `return sleepReply()`.
    /// That made "hi" -- and any other unmatched input -- produce the exact
    /// same sleep summary, which reads as a coach with one canned answer.
    func testAGreetingIsNotAnsweredWithASleepSummary() {
        let evidence = CoachEvidence(night: Fixture.night(timeAsleepMinutes: 400), history: [])
        for greeting in ["hi", "hello", "Hey!", "hi hello", "thanks"] {
            let reply = evidence.reply(to: greeting)
            XCTAssertFalse(
                reply.text.contains("asleep"),
                "\(greeting) was answered with the sleep summary"
            )
            XCTAssertNil(reply.evidence, "a greeting cites no number")
        }
    }

    func testAQuestionOutsideTheDataSaysSoRatherThanAnsweringAnotherOne() {
        let evidence = CoachEvidence(night: Fixture.night(), history: [])
        for question in ["what is the capital of France", "tell me a joke", "who are you"] {
            let reply = evidence.reply(to: question)
            XCTAssertTrue(
                reply.text.lowercased().contains("can only answer"),
                "\(question) did not say what it can answer: \(reply.text)"
            )
            XCTAssertNil(reply.evidence)
        }
    }

    /// The greeting check must not swallow a real question that happens to
    /// contain a short word, and near-miss sleep questions should still get
    /// the night rather than the "I can only answer" line.
    func testRealQuestionsStillReachTheirIntent() {
        let evidence = CoachEvidence(night: Fixture.night(avgHRV: 42), history: [])
        XCTAssertTrue(evidence.reply(to: "ok so why was my HRV low?").text.contains("42"))
        XCTAssertTrue(evidence.reply(to: "why was my sleep bad").text.contains("asleep"))
    }

    func testLocalAnswersMayContainDigitsUnlikeGeneratedProse() {
        XCTAssertFalse(CoachEvidence.allowsGeneratedProse("Your HRV was 42 ms"))
        let reply = CoachEvidence(night: Fixture.night(), history: []).reply(to: "How did I sleep last night?")
        XCTAssertTrue(reply.text.contains("asleep"))
        XCTAssertNotNil(reply.evidence)
    }
}
