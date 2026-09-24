import XCTest

final class AwakeningInspectorTests: XCTestCase {

    private func date(_ h: Int, _ m: Int, second: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 9, day: 14, hour: h, minute: m, second: second)
        )!
    }

    func testOverlappingStreamsStayCoOccurrence() {
        let awake = DateInterval(start: date(2, 43), end: date(2, 50))
        let stages = [
            StageSegment(stage: .core, start: date(1, 0), end: date(2, 43)),
            StageSegment(stage: .awake, start: date(2, 43), end: date(2, 50)),
            StageSegment(stage: .core, start: date(2, 50), end: date(4, 0))
        ]
        let sounds = [SoundEvent(date: date(2, 44), identifier: "snoring", confidence: 0.9)]
        let sequence = AwakeningInspector.inspect(
            awakening: awake,
            stages: stages,
            sounds: sounds,
            heartRateRiseAt: date(2, 41),
            movementAt: date(2, 46)
        )
        XCTAssertTrue(sequence.markers.contains(where: { $0.kind == .hrRise }))
        XCTAssertTrue(sequence.markers.contains(where: { $0.kind == .snore || $0.kind == .soundEnded }))
        XCTAssertTrue(sequence.markers.contains(where: { $0.kind == .stageResume }))
        XCTAssertTrue(sequence.caveat.lowercased().contains("same time"))
        // The caveat must *disclaim* causation, which means the word "caused"
        // appears in it -- "Zoon does not claim that one caused the
        // awakening". Asserting the substring is absent failed the correct
        // sentence and would have passed a caveat that said nothing at all.
        XCTAssertTrue(
            sequence.caveat.lowercased().contains("does not claim"),
            "the caveat has to disclaim causation, not merely avoid the word"
        )
    }

    func testMissingStreamsAreListedNotInvented() {
        let awake = DateInterval(start: date(3, 10), end: date(3, 18))
        let sequence = AwakeningInspector.inspect(awakening: awake, stages: [])
        XCTAssertTrue(sequence.missingStreams.contains("heart rate"))
        XCTAssertTrue(sequence.missingStreams.contains("sound"))
        XCTAssertEqual(sequence.markers.filter { $0.kind == .hrRise }.count, 0)
    }

    func testQuietSoundsAreDropped() {
        let awake = DateInterval(start: date(2, 43), end: date(2, 50))
        let sounds = [SoundEvent(date: date(2, 44), identifier: "snoring", confidence: 0.2)]
        let sequence = AwakeningInspector.inspect(awakening: awake, stages: [], sounds: sounds)
        XCTAssertFalse(sequence.markers.contains(where: { $0.kind == .snore }))
    }

    func testAwakeningsIgnoreMicroWakes() {
        let stages = [
            StageSegment(stage: .awake, start: date(2, 0), end: date(2, 1)),
            StageSegment(stage: .awake, start: date(4, 0), end: date(4, 8))
        ]
        let found = AwakeningInspector.awakenings(in: stages)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.start, date(4, 0))
    }

    /// Was "Light sleep sleep resumed" in the inspector.
    func testResumeCaptionsNeverRepeatSleep() {
        for stage in SleepStage.asleepStages {
            let caption = AwakeningInspector.resumeCaption(for: stage)
            XCTAssertFalse(caption.lowercased().contains("sleep sleep"), caption)
            XCTAssertFalse(caption.lowercased().contains("asleep sleep"), caption)
            XCTAssertTrue(caption.hasSuffix("resumed"), caption)
        }
        XCTAssertEqual(AwakeningInspector.resumeCaption(for: .deep), "Deep sleep resumed")
        XCTAssertEqual(AwakeningInspector.resumeCaption(for: .rem), "REM sleep resumed")
    }
}
