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
