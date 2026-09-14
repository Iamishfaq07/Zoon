import XCTest

/// The watch used to say "Saved" the instant `transferUserInfo` returned.
/// These pin the distinction between "WatchConnectivity took it" and "the
/// phone wrote it down", which is the whole point of the acknowledgement.
final class WatchLogSyncTests: XCTestCase {

    func testOnlySavedCountsAsConfirmed() {
        XCTAssertTrue(WatchLogSyncState.saved.isConfirmed)
        for state: WatchLogSyncState in [.idle, .queued, .sending, .failed(reason: "x")] {
            XCTAssertFalse(state.isConfirmed, "\(state) must not read as a confirmed write")
            XCTAssertNotEqual(state.label, "Saved", "only the phone's word may say Saved")
        }
    }

    func testQueuedAndSendingResolveThemselvesButFailedDoesNot() {
        XCTAssertTrue(WatchLogSyncState.queued.resolvesItself)
        XCTAssertTrue(WatchLogSyncState.sending.resolvesItself)
        XCTAssertFalse(WatchLogSyncState.failed(reason: "no phone").resolvesItself)
        XCTAssertFalse(WatchLogSyncState.saved.resolvesItself)
        XCTAssertFalse(WatchLogSyncState.idle.resolvesItself)
    }

    func testIdleRendersNothing() {
        XCTAssertEqual(WatchLogSyncState.idle.label, "")
        XCTAssertEqual(WatchLogSyncState.idle.symbol, "")
    }

    @MainActor
    func testTrackerKeepsPerLogStateAndLatest() {
        let tracker = WatchLogSyncTracker()
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(tracker.state(for: first), .idle, "an untouched log is idle, not pending")

        tracker.record(first, .queued)
        tracker.record(second, .queued)
        tracker.record(first, .saved)

        XCTAssertEqual(tracker.state(for: first), .saved)
        XCTAssertEqual(tracker.state(for: second), .queued, "one log confirming must not confirm another")
        XCTAssertEqual(tracker.latest?.id, first)
        XCTAssertEqual(tracker.latest?.state, .saved)
    }

    @MainActor
    func testFailAllPendingLeavesSettledLogsAlone() {
        let tracker = WatchLogSyncTracker()
        let queued = UUID()
        let saved = UUID()
        tracker.record(queued, .queued)
        tracker.record(saved, .saved)

        tracker.failAllPending(reason: "Your phone isn't connected.")

        XCTAssertEqual(tracker.state(for: queued), .failed(reason: "Your phone isn't connected."))
        XCTAssertEqual(tracker.state(for: saved), .saved, "a confirmed write cannot be un-confirmed by a session failure")
    }

    @MainActor
    func testClearResetsEverything() {
        let tracker = WatchLogSyncTracker()
        let id = UUID()
        tracker.record(id, .saved)
        tracker.clear()
        XCTAssertEqual(tracker.state(for: id), .idle)
        XCTAssertNil(tracker.latest)
    }

    // MARK: - Acknowledgement

    func testAcknowledgementSurvivesTheWire() throws {
        let id = UUID()
        let data = try JSONEncoder().encode(
            WatchActionAcknowledgement(id: id, accepted: false, reason: "Your phone couldn't file this log.")
        )
        let decoded = try JSONDecoder().decode(WatchActionAcknowledgement.self, from: data)

        XCTAssertEqual(decoded.id, id, "the identifier is the only way to say which log this is about")
        XCTAssertEqual(decoded.state, .failed(reason: "Your phone couldn't file this log."))
    }

    func testAcceptedAcknowledgementIsTheOnlyRouteToSaved() {
        XCTAssertEqual(WatchActionAcknowledgement(id: UUID(), accepted: true).state, .saved)
    }

    func testRejectionWithoutAReasonStillExplainsItself() {
        guard case .failed(let reason) = WatchActionAcknowledgement(id: UUID(), accepted: false).state else {
            return XCTFail("a rejection must map to failed")
        }
        XCTAssertFalse(reason.isEmpty, "the wearer needs to know it did not land")
    }

    // MARK: - Duplicate vs. rejected, on the phone side

    /// `accepts` says no for two very different reasons, and the watch must
    /// be told different things: a redelivery of something already written
    /// succeeded, an out-of-window packet did not.
    func testRedeliveryIsDistinguishableFromRejection() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "zoon.tests.\(UUID().uuidString)"))
        let store = WatchActionReceiptStore(defaults: defaults)
        let event = WatchActionEnvelope(action: .behaviorTag(rawValue: "alcohol"))

        XCTAssertTrue(store.accepts(event))
        XCTAssertFalse(store.hasRecorded(event))

        store.record(event)

        XCTAssertFalse(store.accepts(event), "a second copy must not be applied twice")
        XCTAssertTrue(store.hasRecorded(event), "but it is a log the phone does have")

        let future = WatchActionEnvelope(action: .midnightAwakening, occurredAt: .now.addingTimeInterval(86_400))
        XCTAssertFalse(future.id == event.id)
        XCTAssertFalse(store.accepts(future))
        XCTAssertFalse(store.hasRecorded(future), "a rejected packet was never written and must not read as saved")
    }
}

/// Recovery grades the night that ended. Nothing recomputes it after waking,
/// so the name has to say which moment it belongs to — "Recovery: 71" beside
/// an evening clock reads as a live gauge, which it is not.
final class MorningRecoveryNamingTests: XCTestCase {

    func testAvailableStateIsNamedForTheMorning() {
        let state = RecoveryPresentationState.available(score: 71, confidence: .high)
        XCTAssertEqual(state.title, "Morning Recovery")
        XCTAssertEqual(RecoveryPresentationState.longName, "Morning Recovery")
    }

    func testTimingNoteSaysItDoesNotMove() {
        let note = RecoveryPresentationState.timingNote.lowercased()
        XCTAssertTrue(note.contains("last night"), "the note must pin the score to a night")
        XCTAssertTrue(note.contains("doesn't move") || note.contains("does not move"))
    }

    /// The short name still exists for complications and stat rows, where the
    /// full one would truncate — but it is a deliberate shortening, not the
    /// metric's definition.
    func testShortNameRemainsAvailableForGlanceSurfaces() {
        XCTAssertEqual(RecoveryPresentationState.shortName, "Recovery")
    }
}
