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
        XCTAssertTrue(loaded!.unexpectedEndMessage().contains("preserved"))
        SnoreCheckpoint.clear(defaults: defaults)
        XCTAssertNil(SnoreCheckpoint.load(defaults: defaults))
    }
}
