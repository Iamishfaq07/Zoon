import XCTest

final class SleepSourceArbitrationTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func instant(_ hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: hour, minute: minute))!
    }

    private func sample(
        start: Date,
        end: Date,
        stage: SleepStage,
        priority: SourcePriority,
        id: UUID = UUID(),
        bundle: String = ""
    ) -> SleepSampleRecord {
        SleepSampleRecord(
            id: id,
            start: start,
            end: end,
            stage: stage,
            priority: priority,
            sourceBundleIdentifier: bundle
        )
    }

    func testDuplicateUUIDIsCountedOnce() {
        let id = UUID()
        let a = sample(
            start: instant(23), end: instant(23).addingTimeInterval(8 * 3600),
            stage: .core, priority: .appleWatch, id: id
        )
        let duplicate = SleepSampleRecord(
            id: UUID(), sourceUUID: id,
            start: a.start, end: a.end, stage: .core, priority: .appleWatch
        )
        let fused = SleepSourceArbitration.fuse([a, duplicate])
        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused[0].duration, 8 * 3600, accuracy: 0.5)
    }

    func testWatchWinsOverlapAndPhoneFillsTheLeadingGap() {
        let watchStart = instant(23)
        let watchEnd = instant(23).addingTimeInterval(8 * 3600)
        let phoneStart = instant(22, minute: 30)
        let watch = sample(start: watchStart, end: watchEnd, stage: .core, priority: .appleWatch)
        let phone = sample(start: phoneStart, end: watchEnd, stage: .unspecified, priority: .phoneOrManual)

        let fused = SleepSourceArbitration.fuse([phone, watch])

        XCTAssertEqual(fused.count, 2)
        XCTAssertEqual(fused[0].stage, .unspecified)
        XCTAssertEqual(fused[0].priority, .phoneOrManual)
        XCTAssertEqual(fused[0].start, phoneStart)
        XCTAssertEqual(fused[0].end, watchStart)
        XCTAssertEqual(fused[1].stage, .core)
        XCTAssertEqual(fused[1].priority, .appleWatch)
        XCTAssertEqual(fused[1].start, watchStart)
        XCTAssertEqual(fused[1].end, watchEnd)
    }

    func testDisagreeingStagesAreNotUnioned() {
        let start = instant(1)
        let end = instant(2)
        let watch = sample(start: start, end: end, stage: .deep, priority: .appleWatch)
        let garmin = sample(start: start, end: end, stage: .rem, priority: .thirdPartyWearable)

        let fused = SleepSourceArbitration.fuse([garmin, watch])

        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused[0].stage, .deep)
        XCTAssertEqual(fused[0].priority, .appleWatch)
        XCTAssertEqual(fused[0].duration, 3600, accuracy: 0.5)
    }

    func testWearableBeatsPhoneOnOverlap() {
        let start = instant(23)
        let end = start.addingTimeInterval(7 * 3600)
        let wearable = sample(start: start, end: end, stage: .core, priority: .thirdPartyWearable)
        let phone = sample(start: start, end: end, stage: .unspecified, priority: .phoneOrManual)

        let fused = SleepSourceArbitration.fuse([phone, wearable])
        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused[0].priority, .thirdPartyWearable)
        XCTAssertEqual(fused[0].stage, .core)
    }

    func testSamePriorityKeepsEarlierStartRatherThanMergingStages() {
        let first = sample(
            start: instant(23), end: instant(23).addingTimeInterval(4 * 3600),
            stage: .core, priority: .appleWatch
        )
        let second = sample(
            start: instant(23, minute: 30), end: instant(23).addingTimeInterval(5 * 3600),
            stage: .rem, priority: .appleWatch
        )
        let fused = SleepSourceArbitration.fuse([second, first])

        // First keeps 23:00–03:00 core. Second is clipped to 03:00–04:00 rem.
        XCTAssertEqual(fused.count, 2)
        XCTAssertEqual(fused[0].stage, .core)
        XCTAssertEqual(fused[0].end.timeIntervalSince(fused[0].start), 4 * 3600, accuracy: 0.5)
        XCTAssertEqual(fused[1].stage, .rem)
        XCTAssertEqual(fused[1].start, first.end)
        XCTAssertEqual(fused[1].end, second.end)
    }

    func testZeroDurationSamplesAreDropped() {
        let instant = instant(23)
        let empty = sample(start: instant, end: instant, stage: .awake, priority: .appleWatch)
        let real = sample(
            start: instant, end: instant.addingTimeInterval(6 * 3600),
            stage: .core, priority: .appleWatch
        )
        let fused = SleepSourceArbitration.fuse([empty, real])
        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused[0].stage, .core)
    }

    func testFillGapsDoesNotRewriteTheWinner() {
        let watch = sample(
            start: instant(23), end: instant(23).addingTimeInterval(8 * 3600),
            stage: .deep, priority: .appleWatch
        )
        let phone = sample(
            start: instant(22), end: instant(23).addingTimeInterval(8 * 3600),
            stage: .unspecified, priority: .phoneOrManual
        )
        let fused = SleepSourceArbitration.fillGaps(winner: [watch], candidates: [phone])
        let watchMinutes = fused.filter { $0.priority == .appleWatch }.reduce(0.0) { $0 + $1.duration }
        XCTAssertEqual(watchMinutes, 8 * 3600, accuracy: 0.5)
        XCTAssertEqual(fused.filter { $0.stage == .deep }.count, 1)
    }
}
