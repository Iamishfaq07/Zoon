import Foundation

/// A process-wide signal that Delete Everything has run.
///
/// **The defect this exists for.** Erasing cleared the persisted snore and
/// sound-event keys, but the Snore Check screen owns its own `SnoreDetector`
/// and `SnoreStore`. If a session was listening when the erase ran:
///
/// - the microphone kept running after "everything" was deleted;
/// - the screen's `SnoreStore` still held the erased summaries in memory,
///   and stopping the session called `record`, which re-persisted all of
///   them alongside the new one.
///
/// Every holder of state that can outlive an erase observes this, and every
/// write that could resurrect erased data checks the generation it was loaded
/// under. A write from before the erase is dropped, not merged.
enum DataErasure {

    /// Posted on the main thread after the stores have been cleared.
    static let didErase = Notification.Name("zoon.dataErasure.didErase")

    /// Locked rather than actor-isolated: stores read it from `init`, which
    /// may run on any actor.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func read() -> Int { lock.lock(); defer { lock.unlock() }; return value }
        func increment() { lock.lock(); value += 1; lock.unlock() }
    }
    private static let counter = Counter()

    /// Increments on every erase. A value captured before an erase no
    /// longer matches after it.
    static var generation: Int { counter.read() }

    /// Advances the generation and tells every observer. Called once, by
    /// the coordinator's erase, after persisted data is gone.
    static func announce(center: NotificationCenter = .default) {
        counter.increment()
        center.post(name: didErase, object: nil)
    }
}
