import XCTest

/// The watch → phone wire format.
///
/// These actions cross a process boundary as `Codable` payloads, and a
/// mis-encoded case is not a crash on either side -- it is a tap that
/// silently records nothing, which is the worst failure this app has, since
/// the person believes they logged something and no engine ever sees it.
final class WatchQuickActionTests: XCTestCase {

    private func roundTrip(_ action: WatchQuickAction) throws -> WatchQuickAction {
        let data = try JSONEncoder().encode(action)
        return try JSONDecoder().decode(WatchQuickAction.self, from: data)
    }

    func testAYesAnswerSurvivesTheWire() throws {
        let decoded = try roundTrip(.behaviorAnswer(rawValue: "caffeineLate", happened: true))
        guard case .behaviorAnswer(let tag, let happened) = decoded else {
            return XCTFail("decoded as \(decoded)")
        }
        XCTAssertEqual(tag, "caffeineLate")
        XCTAssertTrue(happened)
    }

    /// The half that a toggle could never have carried.
    func testANoAnswerSurvivesTheWire() throws {
        let decoded = try roundTrip(.behaviorAnswer(rawValue: "alcohol", happened: false))
        guard case .behaviorAnswer(let tag, let happened) = decoded else {
            return XCTFail("decoded as \(decoded)")
        }
        XCTAssertEqual(tag, "alcohol")
        XCTAssertFalse(happened)
    }

    /// An answer and a toggle are different actions and must not decode into
    /// each other: a toggle advances whatever state the tag is in, while an
    /// answer records the one that was pressed. Collapsing them would make
    /// "No" mean "toggle", and a toggle from a tag already answered yes would
    /// record no -- the right answer by accident, and the wrong one whenever
    /// the tag was unanswered.
    func testAnAnswerIsNotATogglOnTheWire() throws {
        let answer = try JSONEncoder().encode(
            WatchQuickAction.behaviorAnswer(rawValue: "alcohol", happened: true)
        )
        let toggle = try JSONEncoder().encode(
            WatchQuickAction.behaviorTag(rawValue: "alcohol")
        )
        XCTAssertNotEqual(answer, toggle)

        let decoded = try JSONDecoder().decode(WatchQuickAction.self, from: toggle)
        if case .behaviorAnswer = decoded {
            XCTFail("a toggle decoded as an explicit answer")
        }
    }

    func testTheExistingActionsStillRoundTrip() throws {
        if case .behaviorTag(let tag) = try roundTrip(.behaviorTag(rawValue: "magnesium")) {
            XCTAssertEqual(tag, "magnesium")
        } else {
            XCTFail("behaviorTag did not survive")
        }
        if case .morningFeeling(let value) = try roundTrip(.morningFeeling(rawValue: 4)) {
            XCTAssertEqual(value, 4)
        } else {
            XCTFail("morningFeeling did not survive")
        }
        if case .nap(let minutes) = try roundTrip(.nap(minutes: 25)) {
            XCTAssertEqual(minutes, 25)
        } else {
            XCTFail("nap did not survive")
        }
        if case .midnightAwakening = try roundTrip(.midnightAwakening) {
            // Encoded as a distinct case so a Double Tap cannot be
            // misread as a nap or a behaviour toggle.
        } else {
            XCTFail("midnightAwakening did not survive")
        }
    }

    /// Every tag the phone can ask about must be expressible as an answer.
    /// The identifier travels as a raw string precisely because
    /// `BehaviorTag` does not exist in the watch target, so nothing else
    /// checks that the two vocabularies still line up.
    func testEveryBehaviourTagCanBeAnswered() throws {
        for tag in BehaviorTag.allCases {
            let decoded = try roundTrip(.behaviorAnswer(rawValue: tag.rawValue, happened: true))
            guard case .behaviorAnswer(let raw, _) = decoded else {
                return XCTFail("\(tag.rawValue) did not survive as an answer")
            }
            XCTAssertEqual(BehaviorTag(rawValue: raw), tag)
        }
    }
}
