import XCTest

final class WindDownGuidanceTests: XCTestCase {

    func testFiveMinutesOfGuidanceIsMoreThanFourCycles() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 30, guidedBreathingMinutes: 5)
        XCTAssertGreaterThan(config.guidedCycles, 4)
        XCTAssertEqual(config.guidedCycles, Int(5 * 60 / WindDownGuidanceConfiguration.cycleSeconds))
        XCTAssertLessThanOrEqual(
            Double(config.guidedCycles) * WindDownGuidanceConfiguration.cycleSeconds,
            5 * 60
        )
    }

    func testTenMinuteGuidanceScalesCycles() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 30, guidedBreathingMinutes: 10)
        XCTAssertGreaterThanOrEqual(config.guidedCycles, 20)
    }

    func testAThirtyMinuteRoutineHasAQuietPhaseAfterGuidance() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 30, guidedBreathingMinutes: 5)
        XCTAssertEqual(config.stage(elapsed: 10), .arrive)
        XCTAssertEqual(config.stage(elapsed: 60), .guided)
        XCTAssertEqual(config.stage(elapsed: 12 * 60), .quiet)
        XCTAssertEqual(config.stage(elapsed: 29 * 60 + 50), .close)
    }

    func testCloseCopyIsNotACelebration() {
        XCTAssertFalse(WindDownGuidanceConfiguration.closeLine.lowercased().contains("well done"))
    }

    func testLaterCyclesGoQuietInNaturalMode() {
        let config = WindDownGuidanceConfiguration(voiceMode: .natural)
        XCTAssertFalse(config.voiceMode.cue(phase: "inhale", cycleIndex: 0).isEmpty)
        XCTAssertEqual(config.voiceMode.cue(phase: "inhale", cycleIndex: 4), "")
    }

    func testHapticsOnlyNeverSpeaks() {
        let config = WindDownGuidanceConfiguration(voiceMode: .hapticsOnly)
        XCTAssertEqual(config.voiceMode.cue(phase: "inhale", cycleIndex: 0), "")
        XCTAssertTrue(config.usesHaptics)
        XCTAssertFalse(config.usesVoice)
    }

    func testGuidedPositionResumesHoldNotArrive() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 30, guidedBreathingMinutes: 5)
        let arrive = config.guidedPosition(elapsed: 10)
        XCTAssertEqual(arrive.phaseName, "arrive")
        let intoFirstCycle = WindDownGuidanceConfiguration.arriveSeconds + 5
        let hold = config.guidedPosition(elapsed: intoFirstCycle)
        XCTAssertEqual(hold.phaseName, "hold")
        XCTAssertEqual(hold.cyclesCompleted, 0)
        XCTAssertGreaterThan(hold.remaining, 0)
        let later = config.guidedPosition(elapsed: WindDownGuidanceConfiguration.arriveSeconds + WindDownGuidanceConfiguration.cycleSeconds + 1)
        XCTAssertEqual(later.cyclesCompleted, 1)
        XCTAssertEqual(later.phaseName, "inhale")
    }

    func testFiveMinuteRoutineCannotTakeFiveMinutesOfGuidance() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 5, guidedBreathingMinutes: 5)
        XCTAssertLessThan(config.guidedBreathingMinutes, 5)
        let span = WindDownGuidanceConfiguration.arriveSeconds
            + config.actualGuidedSeconds
            + WindDownGuidanceConfiguration.closeSeconds
        XCTAssertLessThanOrEqual(span, config.routineSeconds)
    }

    func testTwoMinuteGuidanceDoesNotOverflowItsWindow() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 30, guidedBreathingMinutes: 2)
        XCTAssertLessThanOrEqual(
            Double(config.guidedCycles) * WindDownGuidanceConfiguration.cycleSeconds,
            2 * 60
        )
    }
}
