import XCTest

/// The moments a night is actually made of.
///
/// A hypnogram is a shape, and most people do not decode it. These tests are
/// mostly about what the replay *refuses* to caption: a caption is a claim
/// that something happened, and a night with three interesting moments should
/// play three, not six.
final class SleepReplayTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func segment(_ stage: SleepStage, from: Double, to: Double) -> StageSegment {
        StageSegment(
            stage: stage,
            start: start.addingTimeInterval(from * 60),
            end: start.addingTimeInterval(to * 60)
        )
    }

    /// In bed, asleep, deep, brief flicker, REM, awake, up.
    private var night: [StageSegment] {
        [
            segment(.inBed, from: 0, to: 12),
            segment(.core, from: 12, to: 80),
            segment(.deep, from: 80, to: 140),
            segment(.core, from: 140, to: 142),      // 2 minutes: noise
            segment(.rem, from: 142, to: 200),
            segment(.awake, from: 200, to: 208),
            segment(.core, from: 208, to: 420)
        ]
    }

    // MARK: - What it captions

    func testTheNightOpensWithFallingAsleepAndEndsWithWaking() {
        let moments = SleepReplay.moments(from: night)
        XCTAssertEqual(moments.first?.kind, .fellAsleep)
        XCTAssertEqual(moments.last?.kind, .wokeUp)
        XCTAssertEqual(moments.last?.date, start.addingTimeInterval(420 * 60))
    }

    /// Falling asleep is the first *sleep*, not the first sample. Most nights
    /// open with an in-bed or awake run, and captioning that as sleep onset
    /// would be wrong by however long it took to drop off.
    func testFallingAsleepSkipsTheInBedRun() {
        let moments = SleepReplay.moments(from: night)
        XCTAssertEqual(moments.first?.date, start.addingTimeInterval(12 * 60))
    }

    func testMomentsAreChronological() {
        let moments = SleepReplay.moments(from: night.shuffled())
        XCTAssertEqual(moments, moments.sorted { $0.date < $1.date })
    }

    // MARK: - What it refuses to caption

    /// The reason `minimumRunMinutes` exists. Consumer wearables flip between
    /// adjacent stages constantly; captioning every flip describes the
    /// classifier rather than the night.
    func testAShortStageFlickerIsNotAMoment() {
        let moments = SleepReplay.moments(from: night)
        let twoMinuteFlicker = start.addingTimeInterval(140 * 60)
        XCTAssertFalse(
            moments.contains { $0.date == twoMinuteFlicker },
            "a 2-minute run was captioned"
        )
    }

    /// `unspecified` is what a source writes when it cannot tell you the
    /// stage. Captioning it mid-night would imply a change the data does not
    /// claim.
    func testUnspecifiedSleepIsNotCaptionedAsAStageChange() {
        let unstaged = [
            segment(.inBed, from: 0, to: 10),
            segment(.unspecified, from: 10, to: 400)
        ]
        let moments = SleepReplay.moments(from: unstaged)
        XCTAssertEqual(moments.map(\.kind), [.fellAsleep, .wokeUp])
    }

    func testAnEmptyNightHasNoMoments() {
        XCTAssertTrue(SleepReplay.moments(from: []).isEmpty)
    }

    // MARK: - Sound

    private func sound(atMinute minute: Double, confidence: Double) -> SoundEvent {
        SoundEvent(
            date: start.addingTimeInterval(minute * 60),
            identifier: "snoring",
            confidence: confidence
        )
    }

    func testAConfidentSoundInsideTheNightIsAMoment() {
        let moments = SleepReplay.moments(
            from: night,
            soundEvents: [sound(atMinute: 100, confidence: 0.9)]
        )
        XCTAssertTrue(moments.contains { $0.kind == .sound && $0.caption == "Snoring" })
    }

    /// A caption is a claim that something happened, and the low end of the
    /// classifier's confidence is noise.
    func testAnUnconfidentSoundIsNotCaptioned() {
        let moments = SleepReplay.moments(
            from: night,
            soundEvents: [sound(atMinute: 100, confidence: 0.2)]
        )
        XCTAssertFalse(moments.contains { $0.kind == .sound })
    }

    /// A snore recorded at noon belongs to a different night. Ignored rather
    /// than clamped into this one -- moving it would invent data.
    func testASoundOutsideTheNightIsIgnoredNotClamped() {
        let moments = SleepReplay.moments(
            from: night,
            soundEvents: [sound(atMinute: 900, confidence: 0.95)]
        )
        XCTAssertFalse(moments.contains { $0.kind == .sound })
        XCTAssertEqual(moments.last?.kind, .wokeUp, "the stray event must not become the last moment")
    }

    // MARK: - Pacing

    /// A four-hour night and a ten-hour night should not take the same time
    /// to play -- the pacing is what carries the sense of a long night.
    func testALongerNightPlaysForLonger() {
        XCTAssertGreaterThan(
            SleepReplay.duration(forNightHours: 9),
            SleepReplay.duration(forNightHours: 4)
        )
    }

    func testDurationIsClampedAtBothEnds() {
        XCTAssertEqual(SleepReplay.duration(forNightHours: 0.5), SleepReplay.shortestDurationSeconds)
        XCTAssertEqual(SleepReplay.duration(forNightHours: 24), SleepReplay.longestDurationSeconds)
        for hours in stride(from: 0.0, through: 24.0, by: 0.5) {
            let seconds = SleepReplay.duration(forNightHours: hours)
            XCTAssertGreaterThanOrEqual(seconds, SleepReplay.shortestDurationSeconds)
            XCTAssertLessThanOrEqual(seconds, SleepReplay.longestDurationSeconds)
        }
    }

    // MARK: - Position

    func testFractionPlacesAMomentInTheNight() throws {
        let midpoint = start.addingTimeInterval(210 * 60)
        let fraction = try XCTUnwrap(SleepReplay.fraction(of: midpoint, in: night))
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    func testFractionIsClampedToTheNight() throws {
        let before = try XCTUnwrap(SleepReplay.fraction(of: start.addingTimeInterval(-3600), in: night))
        let after = try XCTUnwrap(SleepReplay.fraction(of: start.addingTimeInterval(9999 * 60), in: night))
        XCTAssertEqual(before, 0)
        XCTAssertEqual(after, 1)
    }

    func testFractionOfAnEmptyNightIsNil() {
        XCTAssertNil(SleepReplay.fraction(of: start, in: []))
    }

    // MARK: - Runs, not segments (V10 item 6)

    /// **The regression.** An ignored micro-run still updated `previousStage`
    /// in a `defer`, so the stretch that resumed afterwards looked like a
    /// fresh transition: Deep, 2 minutes of Core, Deep produced *two* "Deep
    /// sleep" moments for one continuous stretch of deep sleep.
    func testAStretchInterruptedByAMicroRunIsOneMomentNotTwo() {
        // A core run comes first on purpose. The onset moment already
        // captions the first sleep run, and a second caption at the same
        // instant would be noise -- so making the interrupted stretch the
        // *onset* stretch would test the onset guard rather than the
        // micro-run handling this test is about.
        let interrupted = [
            segment(.inBed, from: 0, to: 10),
            segment(.core, from: 10, to: 40),
            segment(.deep, from: 40, to: 70),
            segment(.core, from: 70, to: 72),      // 2 minutes: noise
            segment(.deep, from: 72, to: 97),
            segment(.rem, from: 97, to: 130)
        ]
        let deepMoments = SleepReplay.moments(from: interrupted)
            .filter { $0.caption == SleepStage.deep.displayName }

        XCTAssertEqual(deepMoments.count, 1, "one stretch of deep sleep produced two moments")
        XCTAssertEqual(deepMoments.first?.date, start.addingTimeInterval(40 * 60))
    }

    /// The micro-run is absorbed rather than dropped: the stretch it
    /// interrupted runs through it.
    func testAMicroRunIsAbsorbedIntoTheRunItInterrupted() {
        let runs = SleepReplay.significantRuns(from: [
            segment(.deep, from: 0, to: 30),
            segment(.core, from: 30, to: 32),
            segment(.deep, from: 32, to: 57)
        ])
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.stage, .deep)
        XCTAssertEqual(runs.first?.minutes ?? 0, 57, accuracy: 0.001)
    }

    /// A real transition is still a transition. The fix must not swallow
    /// stage changes that genuinely lasted.
    func testALongStageChangeIsStillItsOwnRun() {
        let runs = SleepReplay.significantRuns(from: [
            segment(.deep, from: 0, to: 30),
            segment(.core, from: 30, to: 50),
            segment(.deep, from: 50, to: 75)
        ])
        XCTAssertEqual(runs.map(\.stage), [.deep, .core, .deep])
    }

    /// Two separate awakenings are two moments, not one.
    func testTwoAwakeningsAreTwoMoments() {
        let moments = SleepReplay.moments(from: [
            segment(.core, from: 0, to: 60),
            segment(.awake, from: 60, to: 68),
            segment(.core, from: 68, to: 140),
            segment(.awake, from: 140, to: 146),
            segment(.core, from: 146, to: 300)
        ])
        XCTAssertEqual(moments.filter { $0.kind == .awoke }.count, 2)
    }

    /// A micro-run with nothing before it has nothing to interrupt, so it is
    /// dropped rather than becoming a run of its own.
    func testAMicroRunBeforeAnythingElseIsDropped() {
        let runs = SleepReplay.significantRuns(from: [
            segment(.awake, from: 0, to: 2),
            segment(.core, from: 2, to: 60)
        ])
        XCTAssertEqual(runs.map(\.stage), [.core])
    }

    /// An unreadable stretch is not a caption, but it *is* a separator: an
    /// hour the source could not stage is not nothing, and the deep sleep on
    /// either side of it is two stretches rather than one.
    func testAnUnspecifiedStretchSeparatesTheRunsAroundItWithoutCaptioningItself() {
        // Again a core run first, so neither deep stretch is the onset run
        // whose caption the "Fell asleep" moment already covers.
        let moments = SleepReplay.moments(from: [
            segment(.core, from: 0, to: 30),
            segment(.deep, from: 30, to: 70),
            segment(.unspecified, from: 70, to: 130),
            segment(.deep, from: 130, to: 180)
        ])
        XCTAssertEqual(moments.filter { $0.caption == SleepStage.deep.displayName }.count, 2)
        XCTAssertFalse(moments.contains { $0.caption == SleepStage.unspecified.displayName })
    }

    func testNoStageDataProducesNoRuns() {
        XCTAssertTrue(SleepReplay.significantRuns(from: []).isEmpty)
    }

    /// The spec's own example output names how long the awakening lasted --
    /// "Awake 6m" -- because "Awake" alone is the one caption where the
    /// duration is the whole point.
    func testAnAwakeningSaysHowLongItLasted() {
        let moments = SleepReplay.moments(from: [
            segment(.core, from: 0, to: 60),
            segment(.awake, from: 60, to: 66),
            segment(.core, from: 66, to: 200)
        ])
        XCTAssertTrue(
            moments.contains { $0.kind == .awoke && $0.caption == "Awake 6m" },
            "captions were \(moments.map(\.caption))"
        )
    }
}
