import XCTest

/// Choosing the single action worth saying, and refusing when there is none.
final class OneThingTests: XCTestCase {

    private func candidate(
        _ kind: OneThing.Kind,
        usefulness: Double = 0.8,
        confidence: MetricConfidence = .high,
        urgency: Double = 0.8,
        consequence: Double = 0.8
    ) -> OneThing.Candidate {
        OneThing.Candidate(
            kind: kind,
            action: "Do \(kind.rawValue)",
            reason: "Because of \(kind.rawValue)",
            usefulness: usefulness,
            confidence: confidence,
            urgency: urgency,
            consequence: consequence
        )
    }

    // MARK: - Picking one

    func testTheStrongestCandidateWins() throws {
        let selection = try XCTUnwrap(OneThing.choose(from: [
            candidate(.morningLight, usefulness: 0.4),
            candidate(.protectWindow, usefulness: 0.9),
            candidate(.moveCaffeineEarlier, usefulness: 0.6),
        ]))
        XCTAssertEqual(selection.candidate.kind, .protectWindow)
        XCTAssertEqual(selection.suppressed.count, 2)
    }

    /// Every chosen action carries its own justification. An imperative the
    /// app cannot explain is one it cannot defend.
    func testTheWinnerCarriesAReason() throws {
        let selection = try XCTUnwrap(OneThing.choose(from: [candidate(.protectWindow)]))
        XCTAssertFalse(selection.candidate.action.isEmpty)
        XCTAssertFalse(selection.candidate.reason.isEmpty)
    }

    /// Saying nothing is a real answer and the common one. A screen that must
    /// always name an action will invent one.
    func testNothingWorthSayingReturnsNothing() {
        XCTAssertNil(OneThing.choose(from: []))
        XCTAssertNil(OneThing.choose(from: [
            candidate(.morningLight, usefulness: 0.9, urgency: 0)
        ]), "an action nobody can take yet is not the one thing")
    }

    // MARK: - The rules the spec names

    /// "Do not surface low-confidence micro-optimizations."
    func testAnEngineThatCannotStandBehindItsAdviceDoesNotCompete() {
        let selection = OneThing.choose(from: [
            candidate(.reduceLoad, usefulness: 1, confidence: .insufficient, urgency: 1, consequence: 1)
        ])
        XCTAssertNil(selection, "insufficient confidence still won the slot")
    }

    func testAMicroOptimisationIsSuppressed() throws {
        let selection = OneThing.choose(from: [
            candidate(.moveCaffeineEarlier, usefulness: 0.9, urgency: 0.9, consequence: 0.05)
        ])
        XCTAssertNil(selection, "a near-consequenceless action was surfaced")

        // But merely uneven advice still counts, or the bar is excluding
        // useful things rather than pointless ones.
        let uneven = try XCTUnwrap(OneThing.choose(from: [
            candidate(.moveCaffeineEarlier, usefulness: 0.9, urgency: 0.9, consequence: 0.1)
        ]))
        XCTAssertEqual(uneven.candidate.kind, .moveCaffeineEarlier)
    }

    /// "Suppress contradictions." Two engines reasoning from different
    /// evidence can both fire on the day after a short night, and telling
    /// somebody to nap and not to nap in one breath is the failure this
    /// exists for.
    func testContradictionsAreNamedAsSuchRatherThanMerelyLosing() throws {
        let selection = try XCTUnwrap(OneThing.choose(from: [
            candidate(.takeRecoveryNap, usefulness: 0.9),
            candidate(.skipLateNap, usefulness: 0.5),
        ]))
        XCTAssertEqual(selection.candidate.kind, .takeRecoveryNap)
        let suppression = try XCTUnwrap(selection.suppressed.first { $0.kind == .skipLateNap })
        XCTAssertEqual(suppression.cause, .contradictedByWinner)
    }

    /// A losing candidate that does not contradict the winner is recorded as
    /// outranked, not as a contradiction -- the distinction is the whole
    /// value of keeping the list.
    func testALoserThatAgreesIsOutrankedNotContradicted() throws {
        let selection = try XCTUnwrap(OneThing.choose(from: [
            candidate(.protectWindow, usefulness: 0.9),
            candidate(.morningLight, usefulness: 0.4),
        ]))
        let suppression = try XCTUnwrap(selection.suppressed.first { $0.kind == .morningLight })
        XCTAssertEqual(suppression.cause, .outranked)
    }

    /// "Suppress repetitive advice." Not by banning it -- a second short
    /// night in a row genuinely still calls for recovery -- but by making it
    /// win by more.
    func testRepeatedAdviceHasToWinByMore() throws {
        let fresh = candidate(.morningLight, usefulness: 0.7)
        let repeated = candidate(.recoverAfterShortNight, usefulness: 0.9)

        let firstTime = try XCTUnwrap(OneThing.choose(from: [fresh, repeated]))
        XCTAssertEqual(firstTime.candidate.kind, .recoverAfterShortNight)

        let afterTwoDays = try XCTUnwrap(OneThing.choose(
            from: [fresh, repeated],
            recentlyShown: [.recoverAfterShortNight, .recoverAfterShortNight]
        ))
        XCTAssertEqual(afterTwoDays.candidate.kind, .morningLight,
                       "the same advice won a third day running")
    }

    func testAdviceGivenThreeDaysRunningStopsCompeting() {
        let selection = OneThing.choose(
            from: [candidate(.recoverAfterShortNight, usefulness: 1, urgency: 1, consequence: 1)],
            recentlyShown: [.recoverAfterShortNight, .recoverAfterShortNight, .recoverAfterShortNight]
        )
        XCTAssertNil(selection)
    }

    /// Rewording an action must not make it novel again, which is why
    /// novelty keys off the kind rather than the string.
    func testNoveltySurvivesRewording() {
        let a = OneThing.Candidate(
            kind: .protectWindow, action: "Protect tonight's 10:45 PM window",
            reason: "r", usefulness: 1, confidence: .high, urgency: 1, consequence: 1
        )
        let b = OneThing.Candidate(
            kind: .protectWindow, action: "Keep your 10:45 window clear",
            reason: "r", usefulness: 1, confidence: .high, urgency: 1, consequence: 1
        )
        XCTAssertEqual(
            OneThing.score(a, recentlyShown: [.protectWindow]),
            OneThing.score(b, recentlyShown: [.protectWindow])
        )
    }

    // MARK: - Arithmetic

    /// A product, not a sum: one worthless term sinks the candidate rather
    /// than being averaged away by four strong ones.
    func testAnyZeroTermSinksTheCandidate() {
        for zeroed in ["usefulness", "urgency", "consequence"] {
            let c = candidate(
                .protectWindow,
                usefulness: zeroed == "usefulness" ? 0 : 1,
                urgency: zeroed == "urgency" ? 0 : 1,
                consequence: zeroed == "consequence" ? 0 : 1
            )
            XCTAssertEqual(OneThing.score(c, recentlyShown: []), 0, "\(zeroed) did not sink it")
        }
    }

    /// A miscomputed factor upstream must not buy a candidate the slot by
    /// arithmetic accident.
    func testFactorsAreClampedOnTheWayIn() {
        let wild = candidate(.reduceLoad, usefulness: 50, urgency: -3, consequence: .nan)
        XCTAssertEqual(wild.usefulness, 1)
        XCTAssertEqual(wild.urgency, 0)
        XCTAssertEqual(wild.consequence, 0)
    }

    /// The same inputs must always give the same answer. A recommendation
    /// that changes when nothing changed reads as the app being unsure.
    func testTiesBreakDeterministically() throws {
        let a = candidate(.morningLight)
        let b = candidate(.protectWindow)
        let first = try XCTUnwrap(OneThing.choose(from: [a, b]))
        let second = try XCTUnwrap(OneThing.choose(from: [b, a]))
        XCTAssertEqual(first.candidate.kind, second.candidate.kind)
    }
}
