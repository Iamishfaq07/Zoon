import XCTest

/// Covers the "multiple physiology callbacks coalesce" requirement.
///
/// Timing-based, so every window is deliberately short and every wait is
/// several times the window -- the assertions are about *how many* refreshes
/// ran, never about precisely when, so a slow CI runner makes these late
/// rather than wrong.
final class HealthRefreshCoalescerTests: XCTestCase {

    /// Refresh closures are `@Sendable` and run across suspensions, so the
    /// count needs somewhere thread-safe to live.
    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private let window: Duration = .milliseconds(100)
    /// Comfortably past the window, so a pending refresh has certainly run.
    private let settleNanoseconds: UInt64 = 500_000_000

    private func settle() async {
        try? await Task.sleep(nanoseconds: settleNanoseconds)
    }

    // MARK: Coalescing

    /// The core case: a watch sync fires sleep plus five physiological
    /// observers within a second or two, and that has to be one refresh.
    @MainActor
    func testBurstOfTriggersProducesOneRefresh() async {
        let counter = Counter()
        let coalescer = HealthRefreshCoalescer(window: window) { await counter.increment() }

        for _ in 0..<6 { coalescer.trigger() }
        await settle()

        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    /// A single trigger still refreshes -- coalescing must not swallow the
    /// one-callback case.
    @MainActor
    func testSingleTriggerRefreshesOnce() async {
        let counter = Counter()
        let coalescer = HealthRefreshCoalescer(window: window) { await counter.increment() }

        coalescer.trigger()
        await settle()

        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    /// Separate syncs are separate refreshes. Once a window closes the next
    /// trigger opens a fresh one, rather than being folded into the last.
    @MainActor
    func testTriggersInSeparateWindowsRefreshTwice() async {
        let counter = Counter()
        let coalescer = HealthRefreshCoalescer(window: window) { await counter.increment() }

        coalescer.trigger()
        await settle()
        coalescer.trigger()
        await settle()

        let count = await counter.value
        XCTAssertEqual(count, 2)
    }

    /// The window is anchored to the *first* trigger and cannot be pushed
    /// back, so a steady drip of updates -- a long watch sync -- still gets a
    /// refresh instead of starving one indefinitely, which is what a
    /// resetting debounce would do here.
    @MainActor
    func testSteadyDripStillRefreshesWithinTheWindow() async {
        let counter = Counter()
        let coalescer = HealthRefreshCoalescer(window: window) { await counter.increment() }

        // Triggers spaced under the window across more than one window's worth
        // of elapsed time. A debounce would have refreshed zero times by now.
        for _ in 0..<8 {
            coalescer.trigger()
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        await settle()

        let count = await counter.value
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    // MARK: Immediate and cancelled

    /// Foreground entry shouldn't sit behind a batching delay meant for
    /// background updates.
    @MainActor
    func testRefreshNowRunsWithoutWaitingOutTheWindow() async {
        let counter = Counter()
        let coalescer = HealthRefreshCoalescer(window: .seconds(30)) { await counter.increment() }

        coalescer.refreshNow()
        try? await Task.sleep(nanoseconds: 200_000_000)

        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    /// Tearing down observers must not leave a refresh queued behind them.
    @MainActor
    func testCancelDropsAPendingRefresh() async {
        let counter = Counter()
        let coalescer = HealthRefreshCoalescer(window: window) { await counter.increment() }

        coalescer.trigger()
        coalescer.cancel()
        await settle()

        let count = await counter.value
        XCTAssertEqual(count, 0)
    }
}
