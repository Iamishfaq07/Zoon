import Foundation

/// Waits for an operation, or for a deadline, whichever comes first -- and
/// really stops waiting when the deadline wins.
///
/// **Why not a task group.** The obvious version races the operation against
/// a sleep inside `withThrowingTaskGroup` and cancels the loser. A task group
/// cannot return until every child has finished, and cancellation is only a
/// request: an operation backed by a completion handler that never fires --
/// HealthKit's authorization call, the case this exists for -- ignores it.
/// The group then waits on that child indefinitely, so the 20-second timeout
/// that was meant to unstick onboarding never returned either.
///
/// Here the operation runs in its own unstructured task and the caller waits
/// on a continuation that is resumed exactly once, by whichever side
/// finishes first. The loser's later result is discarded. The operation is
/// left to complete on its own; a late HealthKit answer is harmless because
/// nothing is waiting on it any more.
enum Deadline {

    struct Expired: Error, Equatable {}

    static func race<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = Gate<T>()
        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            let work = Task {
                do { gate.resume(with: .success(try await operation())) }
                catch { gate.resume(with: .failure(error)) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if gate.resume(with: .failure(Expired())) { work.cancel() }
            }
        }
    }

    /// Resumes its continuation at most once.
    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?

        func install(_ continuation: CheckedContinuation<T, Error>) {
            lock.lock(); defer { lock.unlock() }
            self.continuation = continuation
        }

        /// - Returns: whether this call was the one that resumed.
        @discardableResult
        func resume(with result: Result<T, Error>) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            guard let pending else { return false }
            pending.resume(with: result)
            return true
        }
    }
}
