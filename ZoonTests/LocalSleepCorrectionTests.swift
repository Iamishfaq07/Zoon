import XCTest

final class LocalSleepCorrectionTests: XCTestCase {

    func testNoRepairLeavesTheNightUntouched() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let applied = LocalSleepCorrection.apply(night, repairs: [])
        XCTAssertEqual(applied.bedtime, night.bedtime)
        XCTAssertEqual(applied.wakeTime, night.wakeTime)
        XCTAssertEqual(applied.timeAsleepMinutes, night.timeAsleepMinutes, accuracy: 0.01)
        XCTAssertEqual(applied.timingProvenance, night.timingProvenance)
    }

    func testAnExclusionIsNotABoundaryEdit() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Watch fell off",
            excluded: true,
            bedtimeShiftMinutes: -20
        )
        let applied = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(applied.bedtime, night.bedtime, "an excluded night is dropped, not rewritten")
    }

    func testABedtimeShiftMovesTheWindowAndNotTheAsleepTotal() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Watch started late",
            excluded: false,
            bedtimeShiftMinutes: -20
        )
        let applied = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(applied.bedtime.timeIntervalSince(night.bedtime), -20 * 60, accuracy: 1)
        XCTAssertEqual(applied.timeAsleepMinutes, 450, accuracy: 0.01)
        XCTAssertEqual(applied.timeInBedMinutes, 500, accuracy: 0.5)
        XCTAssertLessThan(applied.sleepEfficiencyPercent, night.sleepEfficiencyPercent)
        assertInvariants(applied)
    }

    func testAShorterWindowClampsAsleepRatherThanInventingADeficitBeyondTheWindow() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Watch kept recording after I got up",
            excluded: false,
            wakeShiftMinutes: -60
        )
        let applied = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(applied.timeInBedMinutes, 420, accuracy: 0.5)
        XCTAssertEqual(applied.timeAsleepMinutes, 420, accuracy: 0.5)
        XCTAssertLessThanOrEqual(applied.timeAsleepMinutes, applied.timeInBedMinutes)
        XCTAssertLessThanOrEqual(applied.stagedAsleepMinutes, applied.timeAsleepMinutes + 0.51)
        assertInvariants(applied)
    }

    func testHealthKitOriginalsAreNotMutated() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let originalBed = night.bedtime
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Adjusted",
            excluded: false,
            bedtimeShiftMinutes: 15
        )
        _ = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(night.bedtime, originalBed)
    }

    func testLegacyRepairJSONWithoutShiftsStillDecodes() throws {
        let json = """
        {"nightKey":"2026-03-01","reason":"Conflict","excluded":true}
        """.data(using: .utf8)!
        let repair = try JSONDecoder().decode(PersonalSetup.Repair.self, from: json)
        XCTAssertEqual(repair.bedtimeShiftMinutes, 0)
        XCTAssertEqual(repair.wakeShiftMinutes, 0)
        XCTAssertTrue(repair.excluded)
        XCTAssertFalse(repair.hasBoundaryEdit)
    }

    // MARK: - Workout timing sign

    func testBedtimeMovedLaterWidensTheWorkoutGap() {
        // Workout 8:00 PM, original bedtime 11:00 PM, gap 3h.
        // Correct bedtime to 11:30 PM → gap 3.5h, not 2.5h.
        let hours = LocalSleepCorrectionMath.workoutHoursBeforeBed(
            originalHours: 3,
            bedtimeShiftMinutes: 30
        )
        XCTAssertEqual(hours ?? -1, 3.5, accuracy: 0.001)
    }

    func testBedtimeMovedEarlierNarrowsTheWorkoutGap() {
        let hours = LocalSleepCorrectionMath.workoutHoursBeforeBed(
            originalHours: 3,
            bedtimeShiftMinutes: -30
        )
        XCTAssertEqual(hours ?? -1, 2.5, accuracy: 0.001)
    }

    func testWorkoutAfterCorrectedBedtimeClearsTheGap() {
        // Original gap 1h, bedtime moved 90 minutes earlier → workout ends
        // after the new bedtime. That is not a late-workout finding.
        XCTAssertNil(
            LocalSleepCorrectionMath.workoutHoursBeforeBed(
                originalHours: 1,
                bedtimeShiftMinutes: -90
            )
        )
    }

    func testALaterBedtimeOnTheNightMovesWorkoutHoursWithIt() {
        let night = Fixture.night(
            daysAgo: 1,
            timeAsleepMinutes: 450,
            timeInBedMinutes: 480,
            lastWorkoutHoursBeforeBed: 3
        )
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Watch started early",
            excluded: false,
            bedtimeShiftMinutes: 30
        )
        let applied = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(applied.lastWorkoutHoursBeforeBed ?? -1, 3.5, accuracy: 0.01)
    }

    func testOvernightBedtimeStillWidensTheGapWhenMovedLater() {
        let night = Fixture.night(
            daysAgo: 1,
            timeAsleepMinutes: 420,
            timeInBedMinutes: 450,
            lastWorkoutHoursBeforeBed: 4,
            bedtimeHour: 23
        )
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 30, wakeShiftMinutes: 0)
        XCTAssertEqual(applied.lastWorkoutHoursBeforeBed ?? -1, 4.5, accuracy: 0.01)
        assertInvariants(applied)
    }

    func testShiftWorkerMorningBedtimeUsesTheSameSign() {
        let night = Fixture.night(
            daysAgo: 1,
            timeAsleepMinutes: 360,
            timeInBedMinutes: 390,
            lastWorkoutHoursBeforeBed: 3,
            bedtimeHour: 8
        )
        let later = night.shiftingBounds(bedtimeShiftMinutes: 30, wakeShiftMinutes: 0)
        XCTAssertEqual(later.lastWorkoutHoursBeforeBed ?? -1, 3.5, accuracy: 0.01)
        let earlier = night.shiftingBounds(bedtimeShiftMinutes: -30, wakeShiftMinutes: 0)
        XCTAssertEqual(earlier.lastWorkoutHoursBeforeBed ?? -1, 2.5, accuracy: 0.01)
    }

    func testMissingWorkoutStaysMissing() {
        XCTAssertNil(
            LocalSleepCorrectionMath.workoutHoursBeforeBed(
                originalHours: nil,
                bedtimeShiftMinutes: 20
            )
        )
    }

    // MARK: - Stage clipping

    func testClippedSegmentsRecomputeStageTotals() {
        let night = stagedNight(
            core: 280, deep: 80, rem: 90,
            trailingWakeMinutes: 30
        )
        XCTAssertEqual(night.timeAsleepMinutes, 450, accuracy: 0.5)
        XCTAssertEqual(night.stagedAsleepMinutes, 450, accuracy: 0.5)

        // Wake 60 minutes earlier clips the last hour (30 REM + 30 awake).
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 0, wakeShiftMinutes: -60)
        XCTAssertEqual(applied.timeInBedMinutes, 420, accuracy: 0.5)
        XCTAssertEqual(applied.timeAsleepMinutes, 420, accuracy: 0.6)
        XCTAssertEqual(applied.coreMinutes, 280, accuracy: 0.6)
        XCTAssertEqual(applied.deepMinutes, 80, accuracy: 0.6)
        XCTAssertEqual(applied.remMinutes, 60, accuracy: 0.6)
        XCTAssertLessThanOrEqual(applied.stagedAsleepMinutes, applied.timeAsleepMinutes + 0.51)
        XCTAssertLessThanOrEqual(applied.timeAsleepMinutes, applied.timeInBedMinutes + 0.01)
        XCTAssertFalse(applied.stageSegments.contains { $0.end > applied.wakeTime.addingTimeInterval(0.5) })
        XCTAssertEqual(applied.timingProvenance, .locallyCorrected)
        assertInvariants(applied)
    }

    func testAShorterWindowWithoutSegmentsScalesStagesInsteadOfLeavingAnImpossibleTotal() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        XCTAssertTrue(night.stageSegments.isEmpty)
        XCTAssertEqual(night.stagedAsleepMinutes, 450, accuracy: 0.5)
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 0, wakeShiftMinutes: -60)
        XCTAssertEqual(applied.timeAsleepMinutes, 420, accuracy: 0.5)
        XCTAssertLessThanOrEqual(applied.stagedAsleepMinutes, applied.timeAsleepMinutes + 0.51)
        XCTAssertTrue(applied.stageSegments.isEmpty, "do not invent a hypnogram")
        assertInvariants(applied)
    }

    func testExpandingTheWindowDoesNotInventStageMinutes() {
        let night = stagedNight(core: 280, deep: 80, rem: 90, trailingWakeMinutes: 30)
        let originalStaged = night.stagedAsleepMinutes
        let applied = night.shiftingBounds(bedtimeShiftMinutes: -20, wakeShiftMinutes: 20)
        XCTAssertEqual(applied.stagedAsleepMinutes, originalStaged, accuracy: 0.5)
        XCTAssertEqual(applied.timeAsleepMinutes, night.timeAsleepMinutes, accuracy: 0.5)
        assertInvariants(applied)
    }

    func testEfficiencyIsRecomputedFromTheCorrectedWindow() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 0, wakeShiftMinutes: -60)
        XCTAssertEqual(applied.sleepEfficiencyPercent, 100, accuracy: 0.2)
        XCTAssertTrue(applied.sleepEfficiencyPercent.isFinite)
        XCTAssertGreaterThanOrEqual(applied.sleepEfficiencyPercent, 0)
        XCTAssertLessThanOrEqual(applied.sleepEfficiencyPercent, 100)
    }

    func testOverlaySetsLocallyCorrectedProvenance() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        XCTAssertEqual(night.timingProvenance, .measured)
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 15, wakeShiftMinutes: 0)
        XCTAssertEqual(applied.timingProvenance, .locallyCorrected)
        XCTAssertEqual(applied.timingProvenance.label, "Locally corrected")
    }

    func testAMissingProvenanceKeyDecodesAsMeasured() throws {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 400, timeInBedMinutes: 420)
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(night)) as! [String: Any]
        object.removeValue(forKey: "timingProvenance")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SleepNightFeatures.self, from: data)
        XCTAssertEqual(decoded.timingProvenance, .measured)
    }

    func testRevertWithoutARepairIsIdentity() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        _ = night.shiftingBounds(bedtimeShiftMinutes: 20, wakeShiftMinutes: -15)
        let reverted = LocalSleepCorrection.apply(night, repairs: [])
        XCTAssertEqual(reverted.bedtime, night.bedtime)
        XCTAssertEqual(reverted.wakeTime, night.wakeTime)
        XCTAssertEqual(reverted.timingProvenance, night.timingProvenance)
    }

    func testClippedLatencyUsesTheRemainingOnset() {
        let night = stagedNight(core: 280, deep: 80, rem: 90, trailingWakeMinutes: 30)
        // Original latency is 12 minutes from Fixture. Moving bedtime 20
        // minutes later eats the latency and then 8 minutes of core.
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 20, wakeShiftMinutes: 0)
        XCTAssertEqual(applied.sleepLatencyMinutes ?? -1, 0, accuracy: 0.6)
        XCTAssertLessThan(applied.coreMinutes, 280)
        assertInvariants(applied)
    }

    func testPercentagesStayAtMostOneHundred() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 90, wakeShiftMinutes: -90)
        XCTAssertLessThanOrEqual(applied.sleepEfficiencyPercent, 100)
        XCTAssertGreaterThanOrEqual(applied.sleepEfficiencyPercent, 0)
        if let deep = applied.deepPercentOfAsleep {
            XCTAssertLessThanOrEqual(deep, 100)
        }
        assertInvariants(applied)
    }

    func testNonFiniteWorkoutHoursAreCleared() {
        XCTAssertNil(
            LocalSleepCorrectionMath.workoutHoursBeforeBed(
                originalHours: .nan,
                bedtimeShiftMinutes: 10
            )
        )
        XCTAssertNil(
            LocalSleepCorrectionMath.workoutHoursBeforeBed(
                originalHours: .infinity,
                bedtimeShiftMinutes: 10
            )
        )
    }

    func testOverlappingSegmentsDoNotLeaveImpossibleTotals() {
        var night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let bed = night.bedtime
        let wake = night.wakeTime
        night = SleepNightFeatures(
            date: night.date,
            bedtime: bed,
            wakeTime: wake,
            timeInBedMinutes: 480,
            timeAsleepMinutes: 450,
            sleepEfficiencyPercent: 450 / 480 * 100,
            coreMinutes: 280,
            deepMinutes: 80,
            remMinutes: 90,
            unspecifiedAsleepMinutes: 0,
            awakeMinutes: 30,
            wakeCount: 1,
            sleepLatencyMinutes: 0,
            avgHeartRate: night.avgHeartRate,
            minHeartRate: night.minHeartRate,
            avgHRV: night.avgHRV,
            avgRespiratoryRate: night.avgRespiratoryRate,
            avgSpO2: night.avgSpO2,
            wristTempDeltaC: night.wristTempDeltaC,
            hrv7DayAvg: night.hrv7DayAvg,
            sleepDebtMinutes: night.sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: 3,
            exerciseMinutesPreviousDay: night.exerciseMinutesPreviousDay,
            sourceName: night.sourceName,
            isMock: true,
            stageSegments: [
                StageSegment(stage: .core, start: bed, end: wake),
                StageSegment(stage: .deep, start: bed, end: wake),
                StageSegment(stage: .rem, start: bed, end: wake)
            ]
        )
        let applied = night.shiftingBounds(bedtimeShiftMinutes: 0, wakeShiftMinutes: -60)
        XCTAssertLessThanOrEqual(applied.stagedAsleepMinutes, applied.timeAsleepMinutes + 0.51)
        XCTAssertLessThanOrEqual(applied.timeAsleepMinutes, applied.timeInBedMinutes + 0.01)
        assertInvariants(applied)
    }

    // MARK: - Helpers

    private func stagedNight(
        core: Double,
        deep: Double,
        rem: Double,
        trailingWakeMinutes: Double
    ) -> SleepNightFeatures {
        let asleep = core + deep + rem
        let inBed = asleep + trailingWakeMinutes
        var night = Fixture.night(
            daysAgo: 1,
            timeAsleepMinutes: asleep,
            timeInBedMinutes: inBed,
            lastWorkoutHoursBeforeBed: 3,
            deepMinutes: deep,
            remMinutes: rem
        )
        let bed = night.bedtime
        let coreEnd = bed.addingTimeInterval(core * 60)
        let deepEnd = coreEnd.addingTimeInterval(deep * 60)
        let remEnd = deepEnd.addingTimeInterval(rem * 60)
        let wake = remEnd.addingTimeInterval(trailingWakeMinutes * 60)
        night = SleepNightFeatures(
            date: night.date,
            bedtime: bed,
            wakeTime: wake,
            timeInBedMinutes: inBed,
            timeAsleepMinutes: asleep,
            sleepEfficiencyPercent: asleep / inBed * 100,
            coreMinutes: core,
            deepMinutes: deep,
            remMinutes: rem,
            unspecifiedAsleepMinutes: 0,
            awakeMinutes: trailingWakeMinutes,
            wakeCount: trailingWakeMinutes > 0 ? 1 : 0,
            sleepLatencyMinutes: 0,
            avgHeartRate: night.avgHeartRate,
            minHeartRate: night.minHeartRate,
            avgHRV: night.avgHRV,
            avgRespiratoryRate: night.avgRespiratoryRate,
            avgSpO2: night.avgSpO2,
            wristTempDeltaC: night.wristTempDeltaC,
            hrv7DayAvg: night.hrv7DayAvg,
            sleepDebtMinutes: night.sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: night.lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: night.exerciseMinutesPreviousDay,
            sourceName: night.sourceName,
            isMock: true,
            stageSegments: [
                StageSegment(stage: .core, start: bed, end: coreEnd),
                StageSegment(stage: .deep, start: coreEnd, end: deepEnd),
                StageSegment(stage: .rem, start: deepEnd, end: remEnd),
                StageSegment(stage: .awake, start: remEnd, end: wake)
            ]
        )
        return night
    }

    private func assertInvariants(_ night: SleepNightFeatures, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(night.timeAsleepMinutes.isFinite, file: file, line: line)
        XCTAssertTrue(night.timeInBedMinutes.isFinite, file: file, line: line)
        XCTAssertTrue(night.sleepEfficiencyPercent.isFinite, file: file, line: line)
        XCTAssertGreaterThanOrEqual(night.timeAsleepMinutes, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(night.timeAsleepMinutes, night.timeInBedMinutes + 0.01, file: file, line: line)
        XCTAssertLessThanOrEqual(night.stagedAsleepMinutes, night.timeAsleepMinutes + 0.51, file: file, line: line)
        XCTAssertGreaterThanOrEqual(night.sleepEfficiencyPercent, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(night.sleepEfficiencyPercent, 100.01, file: file, line: line)
        XCTAssertFalse(night.coreMinutes.isNaN || night.deepMinutes.isNaN || night.remMinutes.isNaN, file: file, line: line)
        if !night.stageSegments.isEmpty {
            XCTAssertFalse(night.stageSegments.contains { $0.end <= $0.start }, file: file, line: line)
            let fromSegments = night.stageSegments
                .filter { SleepStage.asleepStages.contains($0.stage) }
                .reduce(0.0) { $0 + $1.minutes }
            XCTAssertLessThanOrEqual(fromSegments, night.timeInBedMinutes + 0.51, file: file, line: line)
        }
    }
}
