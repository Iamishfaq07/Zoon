import Foundation

/// One SoundAnalysis analyzer run inside a longer Snore Check session.
///
/// `SNClassificationResult.timeRange` is relative to the analyzer, not the
/// session. Rebuilding the analyzer after a call or media-services reset
/// starts that clock near zero again. Adding those local starts into one
/// global list would put a 3am snore on top of the first minute.
struct SoundAnalysisEpoch: Equatable, Sendable {
    /// Session-relative elapsed seconds when this analyzer started.
    let sessionElapsedAtStart: TimeInterval
    let wallClockStart: Date

    func sessionTime(local: TimeInterval) -> TimeInterval {
        sessionElapsedAtStart + max(0, local)
    }

    func date(local: TimeInterval) -> Date {
        wallClockStart.addingTimeInterval(max(0, local))
    }
}
