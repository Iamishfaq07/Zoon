import XCTest
import HealthKit

/// Properties every assembled session must hold, whatever HealthKit hands in.
///
/// The builder's own tests check that particular arrangements of samples
/// produce particular sessions. These check the things that must be true of
/// *any* session — the ones whose violation would put a negative duration, an
/// efficiency over 100%, or more deep sleep than sleep onto a screen.
///
/// The inputs are deliberately hostile: overlapping sources, a sample inside
/// another sample, zero-length samples, stages that disagree with the asleep
/// block containing them, and a night either side of a daylight-saving
/// transition.
final class SleepSessionInvariantTests: XCTestCase {

    private let calendar = Calendar.current
    private let builder = SleepSessionBuilder()

    private func sample(
        _ stage: HKCategoryValueSleepAnalysis,
        _ start: Date,
        _ end: Date
    ) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: stage.rawValue,
            start: start,
            end: max(start, end)
        )
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 1) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    /// Every invariant, applied to one session.
    private func assertSound(
        _ session: SleepSession,
        _ label: String,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            session.timeInBed, 0, "\(label): negative time in bed", line: line
        )
        XCTAssertGreaterThanOrEqual(
            session.totalAsleepMinutes, 0, "\(label): negative asleep time", line: line
        )
        XCTAssertLessThanOrEqual(
            session.totalAsleepMinutes, session.timeInBed / 60 + 0.001,
            "\(label): asleep longer than in bed", line: line
        )
        XCTAssertLessThanOrEqual(
            session.stagedAsleepMinutes, session.totalAsleepMinutes + 0.001,
            "\(label): staged minutes exceed total asleep", line: line
        )
        for stage in [SleepStage.core, .deep, .rem] {
            XCTAssertGreaterThanOrEqual(
                session.minutes(stage), 0, "\(label): negative \(stage) minutes", line: line
            )
            XCTAssertLessThanOrEqual(
                session.minutes(stage), session.totalAsleepMinutes + 0.001,
                "\(label): \(stage) exceeds total asleep", line: line
            )
        }
        XCTAssertFalse(session.totalAsleepMinutes.isNaN, "\(label): NaN asleep", line: line)
        XCTAssertFalse(session.timeInBed.isNaN, "\(label): NaN in bed", line: line)
        XCTAssertFalse(session.timeInBed.isInfinite, "\(label): infinite in bed", line: line)
        XCTAssertLessThanOrEqual(session.start, session.end, "\(label): ends before it starts", line: line)
    }

    private func assertAllSound(_ samples: [HKCategorySample], _ label: String, line: UInt = #line) {
        let sessions = builder.buildSessions(from: samples)
        for session in sessions { assertSound(session, label, line: line) }
    }

    // MARK: - The ordinary shapes

    func testOvernight() {
        assertAllSound([
            sample(.asleepCore, at(5, 23), at(6, 2)),
            sample(.asleepDeep, at(6, 2), at(6, 4)),
            sample(.asleepREM, at(6, 4), at(6, 7)),
        ], "23:00-07:00")
    }

    func testDaySleeper() {
        assertAllSound([
            sample(.asleepCore, at(5, 9), at(5, 13)),
            sample(.asleepDeep, at(5, 13), at(5, 15)),
            sample(.asleepREM, at(5, 15), at(5, 17)),
        ], "09:00-17:00")
    }

    func testEveningIntoNight() {
        assertAllSound([
            sample(.asleepCore, at(5, 17), at(5, 22)),
            sample(.asleepREM, at(5, 22), at(6, 1)),
        ], "17:00-01:00")
    }

    // MARK: - The awkward shapes

    /// Two sources writing the same night. Summing durations here is how an
    /// efficiency over 100% gets made.
    func testOverlappingSourcesDoNotDoubleCount() {
        assertAllSound([
            sample(.asleepCore, at(5, 23), at(6, 4)),
            sample(.asleepCore, at(5, 23), at(6, 4)),
            sample(.asleepDeep, at(6, 1), at(6, 3)),
            sample(.asleepDeep, at(6, 1), at(6, 3)),
        ], "duplicated night")
    }

    /// A stage wholly inside another asleep block.
    func testNestedStagesStayWithinTheirParent() {
        assertAllSound([
            sample(.asleepUnspecified, at(5, 23), at(6, 7)),
            sample(.asleepDeep, at(6, 1), at(6, 2)),
            sample(.asleepREM, at(6, 3), at(6, 4)),
        ], "nested stages")
    }

    func testZeroLengthSamplesDoNotProduceNaN() {
        assertAllSound([
            sample(.asleepCore, at(5, 23), at(5, 23)),
            sample(.asleepCore, at(5, 23), at(6, 6)),
            sample(.inBed, at(6, 6), at(6, 6)),
        ], "zero-length samples")
    }

    func testInBedWithNoAsleepProducesNoSession() {
        let sessions = builder.buildSessions(from: [sample(.inBed, at(5, 23), at(6, 7))])
        XCTAssertTrue(sessions.isEmpty, "a schedule with no sleep in it is not a night")
    }

    /// A long waking gap splits the night; both halves must still be sound.
    func testSplitSleep() {
        assertAllSound([
            sample(.asleepCore, at(5, 22), at(6, 1)),
            sample(.asleepCore, at(6, 4), at(6, 7)),
        ], "split sleep")
    }

    func testNapAfterAShortNight() {
        assertAllSound([
            sample(.asleepCore, at(5, 2), at(5, 5)),
            sample(.asleepCore, at(5, 14), at(5, 15)),
        ], "short night plus nap")
    }

    func testOnlyCoreSleep() {
        assertAllSound([sample(.asleepCore, at(5, 23), at(6, 7))], "core only")
    }

    func testUnstagedSleepOnly() {
        assertAllSound([sample(.asleepUnspecified, at(5, 23), at(6, 7))], "unstaged only")
    }

    // MARK: - Across a daylight-saving transition

    /// These span the instants either side of a US transition, built in a
    /// zone that actually has one -- the CI runner's own zone is UTC, which
    /// does not, so constructing them with `Calendar.current` would have
    /// tested nothing while appearing to.
    ///
    /// What they prove is narrow and worth stating: session assembly works on
    /// instants, so a transition inside a night cannot make a duration
    /// negative or a stage exceed its session. Which *day* such a night is
    /// filed under is a different question, and `SleepDayKeyTests` is where
    /// that is answered.
    private func newYork(_ month: Int, _ day: Int, _ hour: Int) -> Date {
        var zoned = Calendar(identifier: .gregorian)
        zoned.timeZone = TimeZone(identifier: "America/New_York")!
        return zoned.date(from: DateComponents(
            year: 2026, month: month, day: day, hour: hour
        ))!
    }

    func testNightSpanningSpringForward() {
        assertAllSound([
            sample(.asleepCore, newYork(3, 8, 0), newYork(3, 8, 6)),
        ], "spring forward")
    }

    func testNightSpanningFallBack() {
        assertAllSound([
            sample(.asleepCore, newYork(11, 1, 0), newYork(11, 1, 6)),
        ], "fall back")
    }

    // MARK: - Efficiency

    /// The percentage the UI prints, at the boundary where it could exceed
    /// 100 if asleep time were summed rather than merged.
    func testEfficiencyNeverExceedsAHundred() {
        let sessions = builder.buildSessions(from: [
            sample(.inBed, at(5, 23), at(6, 7)),
            sample(.asleepCore, at(5, 23), at(6, 7)),
            sample(.asleepCore, at(5, 23), at(6, 7)),
        ])
        for session in sessions {
            let efficiency = session.timeInBed > 0
                ? session.totalAsleepMinutes / (session.timeInBed / 60) * 100
                : 0
            XCTAssertLessThanOrEqual(efficiency, 100.001, "efficiency over 100%")
            XCTAssertGreaterThanOrEqual(efficiency, 0)
        }
    }

    // MARK: - The cases a real week produces

    /// A sample carrying the timezone HealthKit recorded it in, which is the
    /// only way to tell a travelled night from an ordinary one.
    private func zonedSample(
        _ stage: HKCategoryValueSleepAnalysis,
        _ start: Date,
        _ end: Date,
        zone: String
    ) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: stage.rawValue,
            start: start,
            end: max(start, end),
            metadata: [HKMetadataKeyTimeZone: zone]
        )
    }

    /// A red-eye: slept over the Pacific, woke somewhere nine hours from
    /// where the night began.
    ///
    /// The instants are unambiguous and the invariants follow from that, so
    /// the interesting assertion is the other one -- that the night is filed
    /// under the zone HealthKit recorded, not under wherever the phone
    /// happens to be when the session is next assembled. The runner is UTC
    /// and the flight left Tokyo, and those two disagree about which day
    /// this night belongs to, which is what makes the assertion mean
    /// something rather than pass by coincidence.
    func testRedEyeAcrossTimeZones() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func tokyoTime(_ day: Int, _ hour: Int) -> Date {
            tokyo.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
        }

        let samples = [
            zonedSample(.asleepCore, tokyoTime(5, 23), tokyoTime(6, 2), zone: "Asia/Tokyo"),
            zonedSample(.asleepREM, tokyoTime(6, 2), tokyoTime(6, 4), zone: "Asia/Tokyo"),
            zonedSample(.asleepCore, tokyoTime(6, 4), tokyoTime(6, 6), zone: "Asia/Tokyo"),
        ]
        assertAllSound(samples, "red-eye")

        guard let session = builder.buildSessions(from: samples).first else {
            return XCTFail("the flight produced no session")
        }

        XCTAssertEqual(
            session.timeZoneIdentifier, "Asia/Tokyo",
            "the recorded zone travels with the episode"
        )
        XCTAssertEqual(
            session.nightKey,
            NightKey.make(wakeInstant: session.end, in: TimeZone(identifier: "Asia/Tokyo")!),
            "a travelled night is filed under where it was slept"
        )
        // The key carries its own zone identifier, so comparing whole keys
        // would differ no matter what. The date is the part that matters:
        // 06:00 in Tokyo is still the fifth in UTC, so getting this wrong
        // files the night under the wrong day rather than merely the wrong
        // label.
        XCTAssertTrue(
            session.nightKey.hasPrefix("2026-01-06"),
            "filed under \(session.nightKey), not the Tokyo morning it was"
        )
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(
            utc.dateComponents([.day], from: session.end).day, 5,
            "the runner's zone must actually disagree, or this test proves nothing"
        )
    }

    /// The watch came off at 02:00 and went back on at 05:00 -- three hours
    /// with no samples of any kind.
    ///
    /// That is not three hours of sleep and not three hours of lying awake;
    /// it is three hours nobody measured. The invariant worth stating is
    /// that the builder never counts it: the gap exceeds the session
    /// threshold, so the night splits, and the two halves together account
    /// for five hours rather than eight. Filling the hole would be the
    /// "missing is not zero" failure in its most literal form.
    func testWatchRemovedMidNightIsNotCountedAsSleep() {
        let samples = [
            sample(.asleepCore, at(5, 23), at(6, 2)),
            sample(.asleepCore, at(6, 5), at(6, 7)),
        ]
        assertAllSound(samples, "watch removed mid-night")

        let sessions = builder.buildSessions(from: samples)
        XCTAssertEqual(sessions.count, 2, "an unmeasured gap does not join two halves")

        let measured = sessions.reduce(0.0) { $0 + $1.timeInBed }
        XCTAssertEqual(measured / 3600, 5, accuracy: 0.01, "the uncovered hours were counted")

        let asleep = sessions.reduce(0.0) { $0 + $1.totalAsleepMinutes }
        XCTAssertEqual(asleep, 300, accuracy: 0.01, "asleep time grew to cover the gap")
    }

    /// Awake for fifty minutes at three in the morning, watch on throughout.
    ///
    /// Shorter than the gap threshold, so this stays one night -- the
    /// opposite of the case above, and for the right reason: here the
    /// wakefulness was measured. It has to come out of asleep time without
    /// coming out of the session, which is the arithmetic that puts an
    /// efficiency over 100% on screen when it goes wrong.
    func testLongMiddleOfNightAwakePeriod() {
        let samples = [
            sample(.asleepCore, at(5, 23), at(6, 3)),
            sample(.awake, at(6, 3), at(6, 3, 50)),
            sample(.asleepCore, at(6, 3, 50), at(6, 7)),
        ]
        assertAllSound(samples, "long middle-of-night awake")

        let sessions = builder.buildSessions(from: samples)
        XCTAssertEqual(sessions.count, 1, "measured wakefulness does not split the night")
        guard let session = sessions.first else { return }

        XCTAssertEqual(session.timeInBed / 3600, 8, accuracy: 0.01, "the night is still eight hours")
        XCTAssertEqual(
            session.totalAsleepMinutes, 430, accuracy: 0.01,
            "the fifty awake minutes are still being counted as sleep"
        )
        let awake = session.awakeIntervals.reduce(0.0) { $0 + $1.duration } / 60
        XCTAssertEqual(awake, 50, accuracy: 0.01, "the awake period was not carried through")
    }
}
