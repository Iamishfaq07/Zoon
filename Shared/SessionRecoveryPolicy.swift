import Foundation

/// Ordering contracts for overnight audio recovery.
///
/// The AV objects live in the app target. These flags exist so the
/// "do not close a gap / rebuild owners against a dead session" rules can
/// be tested without AVAudioEngine.
enum AudioSessionResetOrder: Sendable {

    /// Owners may rebuild Soundscape / BreathingCoach / Snore only after
    /// category, mode, and activation have been restored.
    static func shouldNotifyOwners(sessionRestored: Bool) -> Bool {
        sessionRestored
    }
}

enum SnoreResumePolicy: Sendable {

    /// Close an interruption gap only after the engine is running *and*
    /// a real audio buffer has arrived. A failed `engine.start()` must
    /// leave the gap open so monitoring quality does not pretend the
    /// session continued.
    static func shouldCloseGap(engineStarted: Bool, receivedBuffer: Bool) -> Bool {
        engineStarted && receivedBuffer
    }
}

/// Resuming after an interruption (a call, Siri, an alarm) ends.
///
/// Audit §9.3: the coordinator used to run `try? setActive(true)` and then
/// tell every owner to resume whatever happened, so a failed reactivation
/// had owners start engines on a dead session and report themselves playing.
/// Now activation is retried a bounded number of times and owners are told
/// to resume only after it succeeds. A final failure leaves them paused and
/// is reported, never spun on forever.
enum InterruptionResumePolicy: Sendable {

    /// Delay before each activation attempt: at once, then twice with
    /// backoff. Three tries over two seconds -- enough for the common case
    /// where the other app has not quite released the session yet.
    static let attemptDelays: [TimeInterval] = [0, 0.5, 1.5]

    /// Runs the attempts. `activate` throws on failure; `notify` runs only
    /// after a successful activation. Returns whether the session resumed.
    /// Stops early, without notifying, when `shouldContinue` turns false (a
    /// new interruption began, or every owner released).
    ///
    /// `@MainActor` because the closures read and call main-actor audio
    /// owners; a nonisolated async function would run them off the main
    /// actor.
    @MainActor
    static func resume(
        delays: [TimeInterval] = attemptDelays,
        sleep: (TimeInterval) async -> Void,
        shouldContinue: () -> Bool = { true },
        activate: () throws -> Void,
        notify: () -> Void
    ) async -> Bool {
        for delay in delays {
            if delay > 0 { await sleep(delay) }
            guard shouldContinue() else { return false }
            do {
                try activate()
            } catch {
                continue
            }
            notify()
            return true
        }
        return false
    }
}
