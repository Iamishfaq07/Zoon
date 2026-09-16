import XCTest

final class CoachToolCatalogTests: XCTestCase {

    func testReadOnlySleepQuestionDoesNotRequireConfirmation() {
        let call = CoachToolCatalog.interpret("How did I sleep last night?")
        XCTAssertEqual(call?.kind, .getSleepScore)
        XCTAssertEqual(call?.kind.requiresConfirmation, false)
        XCTAssertNil(call?.confirmationPrompt)
    }

    /// The expectation here used to be `5 * 60` — five in the morning — which
    /// pinned the bug rather than the behaviour. A bare hour in a request to
    /// log caffeine is the afternoon: reading it as 05:00 recorded the
    /// exposure as `.caffeine` instead of `.caffeineLate`, understating the
    /// very thing the late-caffeine behaviour exists to capture.
    func testLogCoffeeRequiresConfirmationAndDoesNotInventAScore() {
        let call = CoachToolCatalog.interpret("Log coffee at 5.")
        XCTAssertEqual(call?.kind, .logCaffeine)
        XCTAssertEqual(call?.kind.requiresConfirmation, true)
        XCTAssertTrue(call?.confirmationPrompt?.contains("caffeine") == true)
        XCTAssertEqual(call?.proposedMinutes, 17 * 60)
    }

    /// An explicit meridiem always wins over the assumption.
    func testAnExplicitMorningCaffeineTimeIsTakenAtItsWord() {
        XCTAssertEqual(CoachToolCatalog.interpret("Log coffee at 5 am")?.proposedMinutes, 5 * 60)
        XCTAssertEqual(CoachToolCatalog.interpret("Log coffee at 5 pm")?.proposedMinutes, 17 * 60)
    }

    /// Hours that already say which half of the day they are in are not
    /// shifted: noon and midnight are unambiguous, and so is anything past 12.
    func testUnambiguousHoursAreNotShifted() {
        XCTAssertEqual(CoachToolCatalog.interpret("Log caffeine at 12")?.proposedMinutes, 12 * 60)
        XCTAssertEqual(CoachToolCatalog.interpret("Log caffeine at 16:30")?.proposedMinutes, 16 * 60 + 30)
        XCTAssertEqual(CoachToolCatalog.interpret("Log caffeine at 0")?.proposedMinutes, 0)
    }

    /// The other call site reads a bare hour the other way, because a morning
    /// commitment at "9" is nine in the morning — and `latestMorningEventHour`
    /// would reject a 9 PM one anyway.
    func testABareHourForTomorrowIsReadAsTheMorning() {
        XCTAssertEqual(
            CoachToolCatalog.interpret("Prepare me for my 9 meeting tomorrow")?.proposedMinutes,
            9 * 60
        )
    }

    func testRejectedOrUnknownUtteranceIsNil() {
        XCTAssertNil(CoachToolCatalog.interpret("Tell me a joke"))
    }

    func testNapParsesDurationAndAsksToConfirm() {
        let call = CoachToolCatalog.interpret("Start a 25 minute nap")
        XCTAssertEqual(call?.kind, .startNap)
        XCTAssertEqual(call?.proposedMinutes, 25)
        XCTAssertTrue(call?.kind.requiresConfirmation == true)
    }

    func testTomorrowOpensThePlannerAfterConfirm() {
        let call = CoachToolCatalog.interpret("Prepare me for my 9 AM meeting tomorrow")
        XCTAssertEqual(call?.kind, .prepareTomorrow)
        XCTAssertEqual(call?.proposedMinutes, 9 * 60)
    }

    /// The nap branch used fixed phrases, and "start a 25 minute nap" contains
    /// none of them -- the duration sits between "start a" and "nap". It
    /// returned nil, so `parseNapMinutes` was never even reached.
    func testNapPhrasingWithTheDurationInTheMiddleStillParses() {
        for utterance in [
            "Start a 25 minute nap",
            "start a 40 min nap",
            "take a nap",
            "set a 20 minute nap"
        ] {
            let call = CoachToolCatalog.interpret(utterance)
            XCTAssertEqual(call?.kind, .startNap, "did not recognise: \(utterance)")
            XCTAssertTrue(call?.kind.requiresConfirmation == true)
        }
    }

    /// "nap" inside another word is not a nap request, and a question about a
    /// past nap is not a request to start one.
    func testNapWordAloneDoesNotStartANap() {
        XCTAssertNil(CoachToolCatalog.interpret("how was my nap"))
        XCTAssertNil(CoachToolCatalog.interpret("tell me about kidnapping"))
    }

    /// The regex always captured the minutes and the parser threw them away,
    /// so the feature's own headline example resolved to the wrong time.
    func testMinutesInASpokenTimeAreKept() {
        let call = CoachToolCatalog.interpret("Prepare me for my 8:30 meeting tomorrow")
        XCTAssertEqual(call?.kind, .prepareTomorrow)
        XCTAssertEqual(call?.proposedMinutes, 8 * 60 + 30)
    }

    func testAfternoonTimesResolveWithMeridiem() {
        let call = CoachToolCatalog.interpret("Log coffee at 3:45 pm")
        XCTAssertEqual(call?.kind, .logCaffeine)
        XCTAssertEqual(call?.proposedMinutes, 15 * 60 + 45)
    }

    /// A bare "tomorrow" used to be matched ahead of every read-only branch,
    /// so a question routed into a confirm-to-write tool.
    func testReadQuestionsAreNotRoutedIntoAWrite() {
        for utterance in ["What's my recovery tomorrow", "How did I sleep, and what about tomorrow"] {
            let call = CoachToolCatalog.interpret(utterance)
            XCTAssertEqual(
                call?.kind.requiresConfirmation, false,
                "a question was routed to a write tool: \(utterance)"
            )
        }
    }

    /// `.getTomorrow` was declared and returned by no branch.
    func testTomorrowPlanCanBeRead() {
        let call = CoachToolCatalog.interpret("What's my tomorrow plan")
        XCTAssertEqual(call?.kind, .getTomorrow)
        XCTAssertEqual(call?.kind.requiresConfirmation, false)
        XCTAssertNil(call?.confirmationPrompt)
    }

    /// Every kind the catalog declares must be reachable from some utterance.
    /// This is the test that would have caught `.getTomorrow` on the way in.
    func testEveryKindIsReachable() {
        let utterances = [
            "How did I sleep last night?", "What's my recovery", "Am I behind on sleep",
            "What's my energy now", "When should I sleep", "What's my tomorrow plan",
            "How much have I moved", "Log coffee at 5.", "Start a 25 minute nap",
            "Prepare me for my 9 AM meeting tomorrow", "Set my alarm"
        ]
        let reached = Set(utterances.compactMap { CoachToolCatalog.interpret($0)?.kind })
        // Over `allCases`, not a list beside this one: a tool nobody can ask
        // for is a tool that does not exist, and a hand-written list would
        // simply not mention it.
        for kind in CoachToolCatalog.Kind.allCases {
            XCTAssertTrue(reached.contains(kind), "\(kind.rawValue) is unreachable")
        }
    }

    func testDuplicateCallIsIdempotent() {
        let a = CoachToolCatalog.interpret("What's my recovery")
        let b = CoachToolCatalog.interpret("What's my recovery")
        XCTAssertEqual(a, b)
    }

    // MARK: - The confirmation contract

    /// The safety invariant the whole catalogue exists for: nothing that
    /// changes state may run without being agreed to first.
    ///
    /// Written as a property of the kind rather than of one utterance,
    /// because the failure this guards against is a *new* tool being added
    /// to the enum and quietly defaulting to the read-only branch.
    func testEveryWritingToolRequiresConfirmation() {
        // Iterating every case rather than a list of the writes, which is what
        // this test's own reason for existing requires: a new tool that
        // changes state has to be caught here, and it cannot be if the test
        // has to be told about it first.
        for kind in CoachToolCatalog.Kind.allCases where kind.changesState {
            XCTAssertTrue(kind.requiresConfirmation, "\(kind.rawValue) would run unasked")
        }
    }

    func testNoReadingToolAsksForConfirmation() {
        for kind in CoachToolCatalog.Kind.allCases where !kind.changesState {
            XCTAssertFalse(
                kind.requiresConfirmation,
                "\(kind.rawValue) asks for nothing and should not prompt"
            )
        }
    }

    /// Movement is a read. It reports what a person already did today and
    /// changes nothing, and §27 is explicit that none of it reaches a score.
    func testMovementIsAReadingTool() {
        XCTAssertFalse(CoachToolCatalog.Kind.getMovement.changesState)
        XCTAssertFalse(CoachToolCatalog.Kind.getMovement.requiresConfirmation)
    }

    func testMovementIsReachableFromTheWordsPeopleUse() {
        for utterance in [
            "How many steps today", "How much have I moved", "Have I moved today",
            "What's my movement today"
        ] {
            XCTAssertEqual(
                CoachToolCatalog.interpret(utterance)?.kind, .getMovement, utterance
            )
        }
    }

    /// A proposal a person is asked to agree to has to say what it will do.
    /// A bare "Confirm?" is not consent to anything in particular.
    func testEveryWriteProposesAPromptThatNamesTheAction() throws {
        let utterances = [
            "Log coffee at 5.",
            "Start a 25 minute nap",
            "Prepare me for my 9 AM meeting tomorrow",
            "Set my alarm"
        ]
        for utterance in utterances {
            let call = try XCTUnwrap(CoachToolCatalog.interpret(utterance), utterance)
            let prompt = try XCTUnwrap(call.confirmationPrompt, utterance)
            XCTAssertFalse(prompt.isEmpty)
            XCTAssertTrue(prompt.hasSuffix("?"), "\(prompt) is not a question")
        }
    }

    /// The hour that decides `.caffeine` from `.caffeineLate`, which the
    /// runner reads. It has to match what `BehaviorTag.caffeineLate` calls
    /// itself, or the Coach logs one behaviour and the Journal labels it as
    /// another.
    func testLateCaffeineHourMatchesTheBehaviourItSelects() {
        XCTAssertEqual(CoachToolCatalog.lateCaffeineHour, 16)
        XCTAssertTrue(BehaviorTag.caffeineLate.label.contains("4pm"))
    }

    func testAProposedCaffeineTimeSurvivesIntoThePrompt() throws {
        let call = try XCTUnwrap(CoachToolCatalog.interpret("Log coffee at 5."))
        let minutes = try XCTUnwrap(call.proposedMinutes)
        XCTAssertGreaterThanOrEqual(minutes, CoachToolCatalog.lateCaffeineHour * 60,
                                    "5 in a sleep app is the afternoon")
        let prompt = try XCTUnwrap(call.confirmationPrompt)
        XCTAssertTrue(prompt.contains(CoachToolCatalog.clock(minutes: minutes)), prompt)
    }
}
