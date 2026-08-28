import XCTest

/// How a nap ends when nobody is watching.
///
/// Before this, a nap never ended on its own. `NapStore.finish()` had exactly
/// one caller -- a button in `NapView` -- and the one-second `Task` in that
/// view only ever recomputed a progress ring. So the failure mode was:
/// start a twenty-minute nap, close the app, come back two hours later, tap
/// "I'm awake", and a **two-hour nap** is recorded. That feeds
/// `SleepNeed.napCreditMinutes`, so it then silently cancelled most of
/// tonight's sleep requirement, from a duration nobody ever observed.
@MainActor
final class NapReconciliationTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "zoon.tests.naps.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> NapStore {
        NapStore(defaults: defaults)
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func store(target: Int = 20) -> NapStore {
        let store = makeStore()
        store.start(targetMinutes: target, now: start)
        return store
    }

    // MARK: - The target end is recorded, not recomputed

    func testStartingANapRecordsWhenItShouldEnd() {
        let store = store(target: 20)
        XCTAssertEqual(store.activeNap?.targetEndAt, start.addingTimeInterval(20 * 60))
        XCTAssertEqual(store.activeNap?.targetEnd, start.addingTimeInterval(20 * 60))
    }

    /// A nap persisted by a build predating `targetEndAt` still decodes, and
    /// falls back to deriving the end from start plus target.
    func testALegacyActiveNapWithoutARecordedEndStillResolves() throws {
        let json = Data(#"{"start":0,"targetMinutes":20}"#.utf8)
        let decoded = try JSONDecoder().decode(NapStore.ActiveNap.self, from: json)

        XCTAssertNil(decoded.targetEndAt)
        XCTAssertEqual(decoded.targetEnd, decoded.start.addingTimeInterval(20 * 60))
    }

    // MARK: - Reconciliation

    func testNoNapReconcilesToNothing() {
        XCTAssertEqual(makeStore().reconcile(now: start), NapStore.ReconcileOutcome.none)
    }

    func testANapStillWithinItsTargetIsLeftRunning() {
        let store = store(target: 20)
        XCTAssertEqual(
            store.reconcile(now: start.addingTimeInterval(10 * 60)),
            NapStore.ReconcileOutcome.none
        )
        XCTAssertNotNil(store.activeNap)
    }

    /// Just past the target, the nap closes at the *target*, not at now.
    func testANapJustPastTargetIsClosedAtTheTarget() {
        let store = store(target: 20)
        let outcome = store.reconcile(now: start.addingTimeInterval(25 * 60))

        guard case .finished(let nap) = outcome else {
            return XCTFail("expected finished, got \(outcome)")
        }
        XCTAssertEqual(nap.minutes, 20, accuracy: 0.001,
                       "clamped to the target, not the 25 minutes elapsed")
        XCTAssertNil(store.activeNap)
        XCTAssertEqual(store.naps.count, 1)
    }

    /// The headline regression. Two hours after a twenty-minute nap, nothing
    /// is recorded automatically -- Zoon does not know when the user woke.
    func testANapFoundHoursLaterIsNotRecordedAutomatically() {
        let store = store(target: 20)
        let outcome = store.reconcile(now: start.addingTimeInterval(2 * 3600))

        guard case .needsConfirmation(let pending) = outcome else {
            return XCTFail("expected needsConfirmation, got \(outcome)")
        }
        XCTAssertEqual(pending.targetMinutes, 20)
        XCTAssertEqual(pending.targetEnd, start.addingTimeInterval(20 * 60))
        XCTAssertNil(store.activeNap)
        XCTAssertTrue(store.naps.isEmpty, "nothing is logged until the user answers")
        XCTAssertNotNil(store.pendingNap)
    }

    /// Far enough out that even asking is meaningless.
    func testAnUnrecoverablyStaleNapIsDropped() {
        let store = store(target: 20)
        let outcome = store.reconcile(now: start.addingTimeInterval(9 * 3600))

        XCTAssertEqual(outcome, NapStore.ReconcileOutcome.discarded)
        XCTAssertNil(store.activeNap)
        XCTAssertNil(store.pendingNap)
        XCTAssertTrue(store.naps.isEmpty)
    }

    func testReconcilingTwiceDoesNotDoubleLog() {
        let store = store(target: 20)
        store.reconcile(now: start.addingTimeInterval(25 * 60))
        store.reconcile(now: start.addingTimeInterval(26 * 60))
        XCTAssertEqual(store.naps.count, 1)
    }

    // MARK: - Resolving a pending nap

    func testAcceptingAPendingNapLogsExactlyTheTarget() {
        let store = store(target: 20)
        store.reconcile(now: start.addingTimeInterval(2 * 3600))

        let nap = store.acceptPendingAtTarget()
        XCTAssertEqual(nap?.minutes, 20)
        XCTAssertEqual(store.naps.count, 1)
        XCTAssertNil(store.pendingNap)
    }

    /// "I don't remember" is a real answer, and a gap beats a guess.
    func testDiscardingAPendingNapLogsNothing() {
        let store = store(target: 20)
        store.reconcile(now: start.addingTimeInterval(2 * 3600))

        store.discardPending()
        XCTAssertTrue(store.naps.isEmpty)
        XCTAssertNil(store.pendingNap)
    }

    /// Correcting downward is information; pushing past the target is
    /// describing sleep nothing measured.
    func testResolvingAPendingNapClampsToTheTarget() {
        let store = store(target: 20)
        store.reconcile(now: start.addingTimeInterval(2 * 3600))

        let nap = store.resolvePending(actualEnd: start.addingTimeInterval(90 * 60))
        XCTAssertEqual(nap?.minutes, 20, "cannot claim more than the target")
    }

    func testResolvingAPendingNapAcceptsAShorterRealEnd() {
        let store = store(target: 20)
        store.reconcile(now: start.addingTimeInterval(2 * 3600))

        let nap = store.resolvePending(actualEnd: start.addingTimeInterval(12 * 60))
        XCTAssertEqual(nap?.minutes, 12)
    }

    func testAResolvedNapTooShortToKeepIsNotLogged() {
        let store = store(target: 20)
        store.reconcile(now: start.addingTimeInterval(2 * 3600))

        XCTAssertNil(store.resolvePending(actualEnd: start.addingTimeInterval(30)))
        XCTAssertTrue(store.naps.isEmpty)
    }

    // MARK: - The stop button

    func testFinishingOnTimeRecordsTheRealDuration() {
        let store = store(target: 20)
        let nap = store.finish(now: start.addingTimeInterval(18 * 60))
        XCTAssertEqual(nap?.minutes, 18, "an early wake is real data")
    }

    /// A modest overshoot is ordinary and recorded as-is.
    func testFinishingSlightlyLateRecordsTheOvershoot() {
        let store = store(target: 20)
        let nap = store.finish(now: start.addingTimeInterval(27 * 60))
        XCTAssertEqual(nap?.minutes, 27)
    }

    /// The floor under the button itself, so no single path can turn an
    /// afternoon into a nap even if reconciliation never ran.
    func testFinishingHoursLateIsClamped() {
        let store = store(target: 20)
        let nap = store.finish(now: start.addingTimeInterval(2 * 3600))

        let ceiling = 20 + NapStore.graceMinutes
        XCTAssertEqual(nap?.minutes ?? 0, ceiling, accuracy: 0.001)
        XCTAssertLessThan(nap?.minutes ?? .infinity, 120)
    }

    func testAMistapIsNotLogged() {
        let store = store(target: 20)
        XCTAssertNil(store.finish(now: start.addingTimeInterval(20)))
        XCTAssertTrue(store.naps.isEmpty)
    }

    // MARK: - Erasure

    func testDeleteAllClearsAPendingNap() {
        let store = store(target: 20)
        store.reconcile(now: start.addingTimeInterval(2 * 3600))
        XCTAssertNotNil(store.pendingNap)

        store.deleteAll()
        XCTAssertNil(store.pendingNap)
        XCTAssertNil(store.activeNap)
        XCTAssertTrue(store.naps.isEmpty)
    }

    // MARK: - Persistence

    func testAPendingNapSurvivesARelaunch() {
        let first = store(target: 20)
        first.reconcile(now: start.addingTimeInterval(2 * 3600))

        let second = NapStore(defaults: defaults)
        XCTAssertEqual(second.pendingNap?.targetMinutes, 20)
    }

    /// The old `load()` silently deleted an active nap more than four hours
    /// old. It is now restored and handed to `reconcile`, which reports what
    /// it did instead of deleting in silence.
    func testAnOldActiveNapIsRestoredRatherThanSilentlyDropped() {
        let first = makeStore()
        first.start(targetMinutes: 20, now: Date.now.addingTimeInterval(-6 * 3600))

        let second = NapStore(defaults: defaults)
        XCTAssertNotNil(second.activeNap, "restored, so reconcile can decide")
        XCTAssertEqual(second.reconcile(), NapStore.ReconcileOutcome.discarded)
    }

    // MARK: - The system wake

    /// Records what was asked of the notification layer without touching it.
    /// `NapWake` reaches for `UNUserNotificationCenter.current()`, which traps
    /// outside a real app process -- which is exactly why `NapStore.wake` is
    /// nil by default rather than defaulting to a live one.
    @MainActor
    private final class WakeSpy: NapWakeScheduling {
        var scheduled: [(date: Date, minutes: Int)] = []
        var cancelCount = 0
        var onSchedule: (() -> Void)?

        @discardableResult
        func schedule(at date: Date, targetMinutes: Int) async -> Bool {
            scheduled.append((date, targetMinutes))
            onSchedule?()
            return true
        }

        func cancel() { cancelCount += 1 }
    }

    func testStartingANapArmsAWakeAtTheTarget() async {
        let spy = WakeSpy()
        let armed = expectation(description: "wake scheduled")
        spy.onSchedule = { armed.fulfill() }

        let store = NapStore(defaults: defaults, wake: spy)
        store.start(targetMinutes: 20, now: start)
        await fulfillment(of: [armed], timeout: 2)

        XCTAssertEqual(spy.scheduled.count, 1)
        XCTAssertEqual(spy.scheduled.first?.minutes, 20)
        XCTAssertEqual(spy.scheduled.first?.date, start.addingTimeInterval(20 * 60))
    }

    func testCancellingANapDisarmsTheWake() {
        let spy = WakeSpy()
        let store = NapStore(defaults: defaults, wake: spy)
        store.start(targetMinutes: 20, now: start)
        store.cancel()
        XCTAssertGreaterThanOrEqual(spy.cancelCount, 1)
    }

    func testFinishingANapDisarmsTheWake() {
        let spy = WakeSpy()
        let store = NapStore(defaults: defaults, wake: spy)
        store.start(targetMinutes: 20, now: start)
        store.finish(now: start.addingTimeInterval(18 * 60))
        XCTAssertGreaterThanOrEqual(spy.cancelCount, 1)
    }

    /// A nap closed early by a foreground activation must not leave a
    /// notification armed for a nap that no longer exists.
    func testReconcilingDisarmsTheWake() {
        let spy = WakeSpy()
        let store = NapStore(defaults: defaults, wake: spy)
        store.start(targetMinutes: 20, now: start)
        store.reconcile(now: start.addingTimeInterval(25 * 60))
        XCTAssertGreaterThanOrEqual(spy.cancelCount, 1)
    }

    /// The default really is nil. If this ever regresses to a live `NapWake`,
    /// every test in this file starts building a notification centre inside an
    /// unhosted bundle.
    func testAStoreBuiltWithoutAWakeDoesNotCrashOnStart() {
        let store = NapStore(defaults: defaults)
        store.start(targetMinutes: 20, now: start)
        XCTAssertNotNil(store.activeNap)
    }
}
