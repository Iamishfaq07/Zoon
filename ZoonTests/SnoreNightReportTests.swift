import XCTest

final class SnoreNightReportTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testTheClockPutsEpisodesAfterAnInterruptionAfterIt() {
        var clock = SnoreSessionClock()
        clock.mark(session: 0, wall: t0)
        // Twenty minutes of a phone call: monitored time stops, the wall does not.
        clock.mark(session: 100, wall: t0.addingTimeInterval(1_300))
        XCTAssertEqual(clock.date(at: 50), t0.addingTimeInterval(50))
        XCTAssertEqual(clock.date(at: 150), t0.addingTimeInterval(1_350))
        XCTAssertNil(SnoreSessionClock().date(at: 10))
    }

    func testRecordsJoinCloseSpansAndCarryTheEnginesCountsAndLoudness() {
        var clock = SnoreSessionClock()
        clock.mark(session: 0, wall: t0)
        let fused = [
            SnoreEvidenceFusion.Interval(start: 10, end: 20, source: .heuristic, confidence: 0.4),
            SnoreEvidenceFusion.Interval(start: 24, end: 30, source: .classifier, confidence: 0.8),
            SnoreEvidenceFusion.Interval(start: 100, end: 130, source: .heuristic, confidence: 0.4),
            SnoreEvidenceFusion.Interval(start: 400, end: 420, source: .classifier, confidence: 0.9)
        ]
        let engine = [
            SnoreEpisode(start: 10, end: 20, events: 3, peakAboveFloorDB: 25, scoreTotal: 2),
            SnoreEpisode(start: 100, end: 130, events: 8, peakAboveFloorDB: 8, scoreTotal: 5)
        ]
        let records = SnoreEpisodeRecord.make(fused: fused, engineEpisodes: engine, clock: clock)
        XCTAssertEqual(records.count, 3, "10-20 and 24-30 are one episode")
        XCTAssertEqual(records[0].start, t0.addingTimeInterval(10))
        XCTAssertEqual(records[0].end, t0.addingTimeInterval(30))
        XCTAssertEqual(records[0].events, 3)
        XCTAssertEqual(records[0].loudness, .loud)
        XCTAssertEqual(records[1].loudness, .quiet)
        XCTAssertNil(records[2].events, "only the classifier heard it")
        XCTAssertNil(records[2].loudness)
    }

    func testTheReportSummarisesTheNight() {
        let episodes = [
            SnoreEpisodeRecord(start: t0.addingTimeInterval(3_600), end: t0.addingTimeInterval(4_800), events: 200, loudness: .moderate),
            SnoreEpisodeRecord(start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(900), events: 60, loudness: .quiet),
            SnoreEpisodeRecord(start: t0.addingTimeInterval(9_000), end: t0.addingTimeInterval(9_600), events: 90, loudness: .loud)
        ]
        let report = SnoreNightReport(
            monitoredMinutes: 400,
            snoreMinutes: 35,
            episodes: episodes,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(24_000)
        )
        XCTAssertEqual(report.episodeCount, 3)
        XCTAssertEqual(report.episodes.first?.loudness, .quiet, "sorted by time")
        XCTAssertEqual(report.longest?.duration, 1_200)
        XCTAssertEqual(report.loudest, .loud)
        XCTAssertEqual(report.sharePercent, 9)
        XCTAssertEqual(report.minutesByLoudness.map(\.loudness), [.loud, .moderate, .quiet])
        XCTAssertEqual(report.span?.duration, 24_000)
        XCTAssertEqual(report.position(of: t0.addingTimeInterval(12_000)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(report.position(of: t0.addingTimeInterval(-50)), 0)
    }

    func testTheBusiestHourIsWhereMostSnoringFell() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = calendar.startOfDay(for: t0)
        let episodes = [
            SnoreEpisodeRecord(start: midnight.addingTimeInterval(3_600 + 300), end: midnight.addingTimeInterval(3_600 + 900), events: nil, loudness: nil),
            // Straddles 3am: 10 minutes before, 30 after.
            SnoreEpisodeRecord(start: midnight.addingTimeInterval(3 * 3_600 - 600), end: midnight.addingTimeInterval(3 * 3_600 + 1_800), events: nil, loudness: nil)
        ]
        let report = SnoreNightReport(monitoredMinutes: 300, snoreMinutes: 50, episodes: episodes, startedAt: nil, endedAt: nil)
        XCTAssertEqual(report.busiestHour(calendar: calendar), midnight.addingTimeInterval(3 * 3_600))
        XCTAssertNotNil(report.span, "falls back to the episodes' own span")
    }

    func testAnOlderSummaryWithoutEpisodesHasNoTimeline() {
        let report = SnoreNightReport(monitoredMinutes: 300, snoreMinutes: 20, episodes: nil, startedAt: nil, endedAt: nil)
        XCTAssertNil(report.span)
        XCTAssertEqual(report.episodeCount, 0)
        XCTAssertNil(report.busiestHour())
    }
}
