import XCTest

final class ReviewRegressionTests: XCTestCase {
    func testDelayedWatchEventKeepsItsOccurrenceAndTargetNight() throws {
        let occurrence = Date(timeIntervalSince1970: 1_780_000_000)
        let night = occurrence.addingTimeInterval(-8 * 3600)
        let event = WatchActionEnvelope(action: .morningFeeling(rawValue: 4), occurredAt: occurrence,
            timeZone: TimeZone(identifier: "Asia/Kolkata")!, snapshotDate: night)
        let restored = try JSONDecoder().decode(WatchActionEnvelope.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(restored.targetDate, night)
        XCTAssertEqual(restored.occurredAt, occurrence)
        XCTAssertEqual(restored.calendar.timeZone.identifier, "Asia/Kolkata")
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let receipts = WatchActionReceiptStore(defaults: defaults)
        let delivery = occurrence.addingTimeInterval(2 * 86_400)
        XCTAssertTrue(receipts.accepts(restored, now: delivery))
        receipts.record(restored)
        XCTAssertFalse(receipts.accepts(restored, now: delivery))
        receipts.erase(at: occurrence.addingTimeInterval(60))
        XCTAssertFalse(receipts.accepts(restored, now: delivery))
    }

    /// A packet whose target night is far from its own tap is refused, and
    /// the receipt list stays bounded however many taps arrive.
    func testWatchEnvelopeTargetOutsideItsWindowIsRefusedAndReceiptsAreBounded() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let receipts = WatchActionReceiptStore(defaults: defaults)

        let lastNight = WatchActionEnvelope(action: .morningFeeling(rawValue: 3), occurredAt: now,
                                            snapshotDate: now.addingTimeInterval(-9 * 3600))
        XCTAssertTrue(receipts.accepts(lastNight, now: now))
        for offset in [-15.0 * 86_400, 2 * 86_400, 400 * 86_400] {
            let stray = WatchActionEnvelope(action: .morningFeeling(rawValue: 3), occurredAt: now,
                                            snapshotDate: now.addingTimeInterval(offset))
            XCTAssertFalse(receipts.accepts(stray, now: now), "target \(offset / 86_400) days away")
        }

        for _ in 0..<(WatchActionReceiptStore.receiptLimit + 50) {
            receipts.record(WatchActionEnvelope(action: .morningFeeling(rawValue: 3), occurredAt: now))
        }
        XCTAssertEqual(defaults.stringArray(forKey: "zoon.watch.actionReceipts.v1")?.count,
                       WatchActionReceiptStore.receiptLimit)
    }

    func testAfterMidnightContextIncludesPreviousEvening() {
        let parse = ISO8601DateFormatter()
        let bedtime = parse.date(from: "2026-09-06T00:30:00Z")!
        let wake = parse.date(from: "2026-09-05T07:00:00Z")!
        let coffee = parse.date(from: "2026-09-05T18:00:00Z")!
        let window = SleepContextWindow.waking(before: bedtime, previousWake: wake)
        XCTAssertEqual(window.start, wake)
        XCTAssertTrue(SleepContextWindow.lateCaffeine(before: bedtime, waking: window).contains(coffee))
    }

    func testDaytimeSleepUsesMeasuredWakeInsteadOfMidnight() {
        let bedtime = Date(timeIntervalSince1970: 1_780_000_000)
        let wake = bedtime.addingTimeInterval(-15 * 3600)
        XCTAssertEqual(SleepContextWindow.waking(before: bedtime, previousWake: wake).start, wake)
        XCTAssertEqual(SleepContextWindow.waking(before: bedtime, previousWake: bedtime.addingTimeInterval(-72 * 3600)).duration, 18 * 3600)
    }

    func testSparseNightsDoNotReportErraticRegularity() {
        let nights = (0..<7).map { Fixture.night(daysAgo: $0 * 3) }
        let result = SleepRegularity.compute(nights: nights)
        XCTAssertEqual(result.validPairCount, 0)
        XCTAssertFalse(result.hasEnoughData)
    }
}
