import XCTest

final class SleepStoryTests: XCTestCase {

    private func date(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1 + dayOffset
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func nightWithStaging() -> SleepNightFeatures {
        let bedtime = date(23)
        let onset = date(23, 12)
        let briefWake = date(2)
        let wakeTime = date(7, dayOffset: 1)

        var night = SleepNightFeatures(
            date: date(0, dayOffset: 1),
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: wakeTime.timeIntervalSince(bedtime) / 60,
            timeAsleepMinutes: 450,
            sleepEfficiencyPercent: 94,
            coreMinutes: 400,
            deepMinutes: 30,
            remMinutes: 20,
            unspecifiedAsleepMinutes: 0,
            awakeMinutes: 17,
            wakeCount: 1,
            sleepLatencyMinutes: 12,
            avgHeartRate: 58,
            minHeartRate: 50,
            restingHeartRate: 54,
            avgHRV: 55,
            avgRespiratoryRate: 14.5,
            avgSpO2: 97,
            wristTempDeltaC: 0,
            breathingDisturbances: 1.0,
            hrv7DayAvg: 55,
            sleepDebtMinutes: 0,
            lastWorkoutHoursBeforeBed: nil,
            exerciseMinutesPreviousDay: nil,
            sourceName: "Fixture",
            isMock: true
        )

        night.stageSegments = [
            StageSegment(stage: .inBed, start: bedtime, end: onset),
            StageSegment(stage: .core, start: onset, end: briefWake),
            StageSegment(stage: .awake, start: briefWake, end: briefWake.addingTimeInterval(5 * 60)),
            StageSegment(stage: .core, start: briefWake.addingTimeInterval(5 * 60), end: wakeTime)
        ]
        return night
    }

    func testTimelineIsChronological() {
        let story = SleepStory.build(night: nightWithStaging())
        let times = story.events.map(\.time)
        XCTAssertEqual(times, times.sorted())
    }

    func testIncludesBedtimeAndWakeEvents() {
        let story = SleepStory.build(night: nightWithStaging())
        XCTAssertTrue(story.events.contains { $0.title == "Went to bed" })
        XCTAssertTrue(story.events.contains { $0.title == "Woke for the day" })
        XCTAssertTrue(story.events.contains { $0.title == "Fell asleep" })
    }

    func testShortAwakeningsBelowThresholdAreOmitted() {
        let story = SleepStory.build(night: nightWithStaging(), minimumAwakeMinutes: 10)
        XCTAssertFalse(story.events.contains { $0.title == "Woke briefly" })
    }

    func testLongEnoughAwakeningIsIncluded() {
        let story = SleepStory.build(night: nightWithStaging(), minimumAwakeMinutes: 3)
        XCTAssertTrue(story.events.contains { $0.title == "Woke briefly" })
    }

    func testTagsAppearWhenProvided() {
        let story = SleepStory.build(night: nightWithStaging(), tagLabels: ["Alcohol", "Hard training"])
        let tagEvent = story.events.first { $0.title == "Logged for the day" }
        XCTAssertNotNil(tagEvent)
        XCTAssertEqual(tagEvent?.detail, "Alcohol, Hard training")
    }

    func testNoTagsMeansNoTagEvent() {
        let story = SleepStory.build(night: nightWithStaging())
        XCTAssertFalse(story.events.contains { $0.title == "Logged for the day" })
    }

    func testNapBeforeBedtimeIsIncluded() {
        let night = nightWithStaging()
        let nap = DateInterval(start: date(14), end: date(14, 30))
        let story = SleepStory.build(night: night, napIntervals: [nap])
        XCTAssertTrue(story.events.contains { $0.title == "Napped" })
    }

    func testMissingStageDataStillProducesBedtimeAndWake() {
        let night = Fixture.night(timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let story = SleepStory.build(night: night)
        XCTAssertTrue(story.events.contains { $0.title == "Went to bed" })
        XCTAssertTrue(story.events.contains { $0.title == "Woke for the day" })
        XCTAssertFalse(story.events.contains { $0.title == "Fell asleep" })
    }
}
