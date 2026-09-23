import Foundation

/// One SoundAnalysis analyzer run inside a longer Snore Check session.
///
/// `SNClassificationResult.timeRange` is relative to the analyzer, not the
/// session. Rebuilding the analyzer after a call or media-services reset
/// starts that clock near zero again. Adding those local starts into one
/// global list would put a 3am snore on top of the first minute.
///
/// Session elapsed time and wall-clock time are deliberately different.
/// Elapsed excludes interruption gaps. Wall-clock includes them. Collapsing
/// them by writing `sessionStartedAt + monitoredSeconds` as the wall start
/// maps every post-call event onto the moment the call *began*.
struct SoundAnalysisEpoch: Equatable, Sendable {
    /// Session-relative elapsed seconds when this analyzer started.
    let sessionElapsedAtStart: TimeInterval
    let wallClockStart: Date

    /// A new analyzer that starts *now*, after `sessionElapsed` of actual
    /// monitoring. Wall-clock is `now`, not start + elapsed.
    static func beginningNow(sessionElapsed: TimeInterval, now: Date = .now) -> SoundAnalysisEpoch {
        SoundAnalysisEpoch(sessionElapsedAtStart: sessionElapsed, wallClockStart: now)
    }

    func sessionTime(local: TimeInterval) -> TimeInterval {
        sessionElapsedAtStart + max(0, local)
    }

    func date(local: TimeInterval) -> Date {
        wallClockStart.addingTimeInterval(max(0, local))
    }
}
