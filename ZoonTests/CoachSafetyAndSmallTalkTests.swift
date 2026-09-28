import XCTest

/// The Coach's deterministic front door: safety questions answered the same
/// way whatever tool keyword they contain, and ordinary small talk answered as
/// small talk rather than with a capabilities list or a data dump.
final class CoachSafetyAndSmallTalkTests: XCTestCase {

    // MARK: - Safety

    func testCrisisMessagesGetSupportNotStatistics() {
        for message in ["I want to die", "I've been thinking about suicide", "I want to hurt myself tonight"] {
            XCTAssertEqual(CoachSafety.triage(message), .crisis, message)
        }
        let reply = CoachSafety.reply(for: .crisis)
        XCTAssertTrue(reply.contains("emergency number"))
        XCTAssertFalse(reply.lowercased().contains("hrv"))
        XCTAssertFalse(reply.contains("%"))
    }

    /// The tool keyword ("HRV") used to win, and chest pain got an HRV answer.
    func testUrgentSymptomsWinOverToolKeywords() {
        XCTAssertEqual(CoachSafety.triage("My HRV dropped and I have chest pain at night"), .urgentSymptom)
        XCTAssertEqual(CoachSafety.triage("I can’t breathe properly when I wake up"), .urgentSymptom,
                       "a curly apostrophe from the iPhone keyboard must still match")
    }

    func testMedicalConditionQuestionsGetAReferralEvenWithAToolKeyword() {
        XCTAssertEqual(CoachSafety.triage("Do I have sleep apnea? My breathing disturbances are high"), .medicalCondition)
        XCTAssertTrue(CoachSafety.reply(for: .medicalCondition).contains("doctor"))
    }

    func testDosingQuestionsAreNotAnswered() {
        XCTAssertEqual(CoachSafety.triage("How much melatonin should I take?"), .medicationDosing)
        XCTAssertNil(CoachSafety.triage("Did my sleep aid help last night?"),
                     "asking what a logged behaviour did is an evidence question, not dosing")
    }

    func testOrdinaryQuestionsPassThrough() {
        for question in ["How did I sleep?", "Why am I tired?", "Should I sleep earlier tonight?", "What changed this week?"] {
            XCTAssertNil(CoachSafety.triage(question), question)
        }
    }

    func testEverySafetyReplyPassesTheDiagnosticGuard() {
        for triage in [CoachSafety.Triage.crisis, .urgentSymptom, .medicalCondition, .medicationDosing] {
            XCTAssertFalse(DiagnosticLanguageGuard.rejects(CoachSafety.reply(for: triage)), "\(triage)")
        }
    }

    // MARK: - Small talk

    func testCommonGreetingsAreGreetings() {
        for utterance in ["Good morning", "good morning!", "Hey Zoon", "hi zoon", "Morning", "How are you?", "how’s it going"] {
            XCTAssertEqual(CoachIntentRouter.classify(utterance), .greeting, utterance)
        }
    }

    func testGoodNightIsAFarewell() {
        XCTAssertEqual(CoachIntentRouter.classify("Good night"), .farewell)
    }

    func testAGreetingInFrontOfAQuestionStillRoutesTheQuestion() {
        guard case .tool(let call) = CoachIntentRouter.classify("Good morning, what's my Recovery?") else {
            return XCTFail("the question after the greeting was lost")
        }
        XCTAssertEqual(call.kind, .getRecovery)
    }

    func testWordsThatMerelyStartLikeAGreetingAreNotStripped() {
        XCTAssertEqual(CoachIntentRouter.strippingLeadingGreeting("hint for tonight"), "hint for tonight")
    }

    func testALongerQuestionIsNotSmallTalk() {
        XCTAssertNotEqual(CoachIntentRouter.classify("how are you calculating my sleep score"), .greeting)
    }

    func testRepliesAnswerTheGreetingAndNeverAnalyseSleep() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 7))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 21))!

        XCTAssertTrue(CoachIntentRouter.greetingReply(to: "Good morning", at: morning, calendar: calendar).hasPrefix("Good morning"))
        XCTAssertTrue(CoachIntentRouter.greetingReply(to: "hi", at: evening, calendar: calendar).hasPrefix("Good evening"))
        XCTAssertTrue(CoachIntentRouter.greetingReply(to: "How are you?", at: morning, calendar: calendar).hasPrefix("I'm good"))
        for reply in [CoachIntentRouter.greetingReply(to: "hey", at: morning, calendar: calendar),
                      CoachIntentRouter.greetingReply(to: "hey", at: evening, calendar: calendar)] {
            XCTAssertFalse(reply.contains("%"))
            XCTAssertNil(reply.range(of: #"\d"#, options: .regularExpression), "a greeting reply states no numbers")
        }
    }
}
