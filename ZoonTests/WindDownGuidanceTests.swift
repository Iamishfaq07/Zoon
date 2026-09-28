import XCTest

final class WindDownGuidanceTests: XCTestCase {

    /// Five minutes of guided breathing is still five minutes, but 4-7-8 is
    /// capped at its own guidance (eight cycles at most) and the rest is slow
    /// paced breathing. It used to be fourteen 4-7-8 cycles in a row.
    func testFourSevenEightIsCappedAndTheRestOfTheMinutesIsPacedBreathing() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 30, guidedBreathingMinutes: 5)
        XCTAssertEqual(config.guidedCycles, WindDownGuidanceConfiguration.maximumGuidedCycles)
        XCTAssertEqual(config.actualGuidedSeconds + config.pacedBreathingSeconds, 5 * 60, accuracy: 0.001)
        XCTAssertLessThanOrEqual(config.actualGuidedSeconds, 5 * 60)
    }

    func testTenMinutesOfGuidanceDoesNotMeanTwentyCyclesOfFourSevenEight() {
        let config = WindDownGuidanceConfiguration(routineDurationMinutes: 30, guidedBreathingMinutes: 10)
        XCTAssertEqual(config.guidedCycles, WindDownGuidanceConfiguration.maximumGuidedCycles)
        XCTAssertEqual(config.pacedBreathingSeconds, 10 * 60 - config.actualGuidedSeconds, accuracy: 0.001)
        XCTAssertEqual(config.stage(elapsed: WindDownGuidanceConfiguration.arriveSeconds + 9 * 60), .guided,
                       "the paced minutes are still the guided stage")
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

    /// Cues used to stop after the second cycle, leaving the rest of the
    /// breathing unpaced on a locked screen.
    func testEveryCycleIsPacedWithVoice() {
        for mode in [WindDownGuidanceConfiguration.VoiceMode.natural, .minimal] {
            for cycle in 0..<WindDownGuidanceConfiguration.maximumGuidedCycles {
                for phase in ["inhale", "hold", "exhale"] {
                    XCTAssertFalse(mode.cue(phase: phase, cycleIndex: cycle).isEmpty, "\(mode) \(phase) \(cycle)")
                }
            }
        }
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
