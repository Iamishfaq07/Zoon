import XCTest

final class SnoreCheckpointTests: XCTestCase {

    func testCheckpointRoundTripDoesNotStoreAudio() {
        let defaults = UserDefaults(suiteName: "zoon.snore.checkpoint.tests")!
        defaults.removePersistentDomain(forName: "zoon.snore.checkpoint.tests")
        let checkpoint = SnoreCheckpoint(
            sessionID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            lastCheckpoint: Date(timeIntervalSince1970: 1_180),
            monitoredSeconds: 9_420,
            snoreSeconds: 600,
            heuristicSeconds: 400,
            classifierSeconds: 500,
            interruptionGaps: 1,
            classifierAvailable: true,
            windows: [SnoreClassificationWindow(start: 120, duration: 6, confidence: 0.9, identifier: "snoring")],
            unexpectedEnd: true
        )
        checkpoint.save(defaults: defaults)
        let loaded = SnoreCheckpoint.load(defaults: defaults)
        XCTAssertEqual(loaded?.monitoredSeconds, 9_420)
        XCTAssertEqual(loaded?.windows.count, 1)
        XCTAssertTrue(loaded?.unexpectedEnd == true)
        XCTAssertTrue(loaded!.unexpectedEndMessage().contains("preserved") || loaded!.unexpectedEndMessage().contains("monitored"))
        XCTAssertEqual(loaded?.timezoneIdentifier, nil)
        SnoreCheckpoint.clear(defaults: defaults)
        XCTAssertNil(SnoreCheckpoint.load(defaults: defaults))
    }

    func testCheckpointKeepsGapIntervalsAndTimezone() throws {
        let defaults = UserDefaults(suiteName: "zoon.snore.checkpoint.gaps")!
        defaults.removePersistentDomain(forName: "zoon.snore.checkpoint.gaps")
        let start = Date(timeIntervalSince1970: 1_000)
        let checkpoint = SnoreCheckpoint(
            sessionID: UUID(),
            startedAt: start,
            lastCheckpoint: start.addingTimeInterval(8_400),
            monitoredSeconds: 7_200,
            snoreSeconds: 600,
            heuristicSeconds: 400,
            classifierSeconds: 500,
            interruptionGaps: 1,
            gaps: [SnoreMonitoringGap(startedAt: start.addingTimeInterval(7_200), endedAt: start.addingTimeInterval(8_400))],
            classifierAvailable: true,
            windows: [],
            unexpectedEnd: true,
            timezoneIdentifier: "Asia/Kolkata",
            nightKey: "2026-09-21@Asia/Kolkata",
            monitoringQuality: .moderate
        )
        checkpoint.save(defaults: defaults)
        let loaded = SnoreCheckpoint.load(defaults: defaults)
        XCTAssertEqual(loaded?.gaps.count, 1)
        XCTAssertEqual(try XCTUnwrap(loaded?.gaps.first).duration, 1_200, accuracy: 0.01)
        XCTAssertEqual(loaded?.timezoneIdentifier, "Asia/Kolkata")
        XCTAssertEqual(loaded?.nightKey, "2026-09-21@Asia/Kolkata")
        XCTAssertEqual(loaded?.monitoringQuality, .moderate)
        SnoreCheckpoint.clear(defaults: defaults)
    }

    func testCheckpointKeepsEpisodesSoACrashKeepsWhenAsWellAsHowMuch() throws {
        let defaults = UserDefaults(suiteName: "zoon.snore.checkpoint.episodes")!
        defaults.removePersistentDomain(forName: "zoon.snore.checkpoint.episodes")
        let start = Date(timeIntervalSince1970: 1_000)
        let episodes = [
            SnoreEpisodeRecord(start: start.addingTimeInterval(600), end: start.addingTimeInterval(900), events: 70, loudness: .moderate)
        ]
        SnoreCheckpoint(
            sessionID: UUID(), startedAt: start, lastCheckpoint: start.addingTimeInterval(1_200),
            monitoredSeconds: 1_200, snoreSeconds: 300, heuristicSeconds: 300, classifierSeconds: 0,
            interruptionGaps: 0, classifierAvailable: false, windows: [], unexpectedEnd: true,
            episodes: episodes
        ).save(defaults: defaults)
        let loaded = try XCTUnwrap(SnoreCheckpoint.load(defaults: defaults))
        XCTAssertEqual(loaded.episodes, episodes)
        SnoreCheckpoint.clear(defaults: defaults)
    }
}
