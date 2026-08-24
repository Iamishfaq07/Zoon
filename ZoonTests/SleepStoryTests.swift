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
        let briefWake = date(2, dayOffset: 1)
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

    func testSoundEventOutsideSleepWindowIsExcluded() {
        let night = nightWithStaging()
        let event = SoundEvent(date: date(20), identifier: "snoring", confidence: 0.9)
        let story = SleepStory.build(night: night, soundEvents: [event])
        XCTAssertFalse(story.events.contains { $0.title == "Snoring" })
    }

    func testCloseSoundEventsOfSameCategoryAreGrouped() {
        let night = nightWithStaging()
        let start = date(1, dayOffset: 1)
        let events = [
            SoundEvent(date: start, identifier: "snoring", confidence: 0.9),
            SoundEvent(date: start.addingTimeInterval(120), identifier: "snoring", confidence: 0.9),
            SoundEvent(date: start.addingTimeInterval(240), identifier: "snoring", confidence: 0.9)
        ]
        let story = SleepStory.build(night: night, soundEvents: events)
        let snoreEvents = story.events.filter { $0.title == "Snoring" }
        XCTAssertEqual(snoreEvents.count, 1)
        XCTAssertEqual(snoreEvents.first?.detail, "3 times over 0h 4m")
    }

    /// `Event.id` used to be the bare `Date`. A nap ending exactly one
    /// second before bedtime shares its start instant with the "Logged for
    /// the day" event, which is deliberately placed at
    /// `bedtime.addingTimeInterval(-1)` -- two genuinely different events,
    /// same timestamp. With a bare-Date id, `ForEach(events, id: \.id)`
    /// would treat them as the same identity and drop one. The id is now a
    /// composite of time, title, and symbol, so distinct events at the same
    /// instant stay distinct.
    func testEventsAtTheSameInstantHaveDistinctIDs() {
        let night = nightWithStaging()
        let nap = DateInterval(start: night.bedtime.addingTimeInterval(-1), duration: 20 * 60)
        let story = SleepStory.build(night: night, tagLabels: ["Alcohol"], napIntervals: [nap])

        let napped = story.events.first { $0.title == "Napped" }
        let logged = story.events.first { $0.title == "Logged for the day" }
        XCTAssertNotNil(napped)
        XCTAssertNotNil(logged)
        XCTAssertEqual(napped?.time, logged?.time, "the test setup should actually collide the timestamps")
        XCTAssertNotEqual(napped?.id, logged?.id)

        let ids = Set(story.events.map(\.id))
        XCTAssertEqual(ids.count, story.events.count, "every event in the story must have a unique id")
    }

    func testDistantSoundEventsOfSameCategoryAreNotGrouped() {
        let night = nightWithStaging()
        let events = [
            SoundEvent(date: date(1, dayOffset: 1), identifier: "snoring", confidence: 0.9),
            SoundEvent(date: date(4, dayOffset: 1), identifier: "snoring", confidence: 0.9)
        ]
        let story = SleepStory.build(night: night, soundEvents: events)
        XCTAssertEqual(story.events.filter { $0.title == "Snoring" }.count, 2)
    }

    func testSoundEventNearAwakeningMentionsItWithoutClaimingCausation() {
        let night = nightWithStaging()
        // The fixture's brief awakening starts at 2:00am on day+1.
        let event = SoundEvent(date: date(2, 1, dayOffset: 1), identifier: "cough", confidence: 0.8)
        let story = SleepStory.build(night: night, soundEvents: [event], minimumAwakeMinutes: 3)
        let coughEvent = story.events.first { $0.title == "Coughing" }
        XCTAssertEqual(coughEvent?.detail, "occurred near a brief awakening")
        XCTAssertFalse((coughEvent?.detail ?? "").lowercased().contains("caused"))
        XCTAssertFalse((coughEvent?.detail ?? "").lowercased().contains("woke"))
    }
}
