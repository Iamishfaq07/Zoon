import Foundation

/// Collapses a burst of HealthKit observer callbacks into a single refresh.
///
/// After an Apple Watch syncs, the overnight types do not land together.
/// Sleep stages arrive, then resting heart rate, then HRV, then respiration,
/// then wrist temperature -- each one firing its own observer, seconds apart.
/// Running a full refresh per callback means five or six passes over the same
/// night, each issuing its own set of physiological queries, for one sync.
///
/// This batches them: the first trigger opens a window, every trigger inside
/// that window is absorbed, and one refresh runs when it closes.
///
/// ## Why a fixed window rather than a resetting debounce
///
/// A debounce that restarts its timer on every trigger can be starved
/// indefinitely by a steady drip of updates -- exactly the shape of a long
/// watch sync -- and the refresh never runs at all. A window anchored to the
/// *first* trigger cannot be pushed back, so a refresh always happens within
/// ``window`` of the first change, however many follow it.
///
/// Not an `actor`: it exists to serialise against a `@MainActor` refresh, and
/// hopping to an actor only to hop back would add a suspension point without
/// adding safety.
@MainActor
final class HealthRefreshCoalescer {

    /// How long to absorb further triggers before refreshing.
    ///
    /// Long enough to catch the physiological types trailing a sleep sync,
    /// short enough that a foregrounded app still feels responsive. This is a
    /// batching delay on a background data update, not on anything the user is
    /// waiting behind.
    static let defaultWindow: Duration = .seconds(10)

    private let window: Duration
    private let refresh: @Sendable () async -> Void

    /// The open window, or `nil` when idle. Its presence *is* the "a refresh is
    /// already coming" flag.
    private var pending: Task<Void, Never>?

    /// Set when a trigger lands while a refresh is mid-flight. That refresh may
    /// already have read the data the trigger refers to, or may not have --
    /// rather than reason about it, run once more afterwards.
    private var triggeredDuringRefresh = false
    private var isRefreshing = false

    init(
        window: Duration = HealthRefreshCoalescer.defaultWindow,
        refresh: @escaping @Sendable () async -> Void
    ) {
        self.window = window
        self.refresh = refresh
    }

    deinit { pending?.cancel() }

    /// Records that something changed. Cheap, and safe to call per callback.
    func trigger() {
        if isRefreshing {
            triggeredDuringRefresh = true
            return
        }
        // A window is already open: this trigger is absorbed into it. This is
        // the whole point -- do nothing.
        guard pending == nil else { return }

        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.window)
            guard !Task.isCancelled else { return }
            await self.runRefresh()
        }
    }

    /// Runs the refresh immediately, cancelling any open window.
    ///
    /// For foreground entry, where waiting out a batching delay would show
    /// stale numbers to somebody actually looking at the screen.
    func refreshNow() {
        pending?.cancel()
        pending = nil
        Task { await runRefresh() }
    }

    /// Drops any pending refresh. Used when tearing down observers.
    func cancel() {
        pending?.cancel()
        pending = nil
        triggeredDuringRefresh = false
    }

    private func runRefresh() async {
        pending = nil
        guard !isRefreshing else {
            triggeredDuringRefresh = true
            return
        }
        isRefreshing = true
        await refresh()
        isRefreshing = false

        if triggeredDuringRefresh {
            triggeredDuringRefresh = false
            trigger()
        }
    }
}
