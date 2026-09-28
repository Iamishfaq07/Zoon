import Foundation
import AVFoundation
import SoundAnalysis
import os

/// Wraps Apple's built-in on-device sound classifier (`SNClassifySoundRequest`,
/// the same taxonomy that ships with the OS -- no bundled model, no download,
/// consistent with every other on-device claim this app makes) to turn the
/// raw audio buffers `SnoreDetector` already taps into a timestamped stream
/// of recognized sound categories.
///
/// Same audio, second observer: this doesn't install its own microphone tap.
/// `SnoreDetector` feeds it the identical buffers its own heuristic already
/// processes, so there is no second permission prompt and no second stream
/// of raw audio anywhere -- only this class's derived (identifier,
/// confidence, time range) triples, handed back through `onEvent`, survive
/// past the buffer they were measured in.
///
/// Three threads touch it: `start`/`stop` on the main actor, `process` on the
/// audio tap's thread, and result callbacks on SoundAnalysis's. Two locks,
/// which is what the `@unchecked Sendable` below is claiming:
///
/// - `analysisLock` owns `analyzer`. It serialises `analyze` against `start`
///   and `stop`, and it is the only lock ever held while calling into
///   SoundAnalysis.
/// - `stateLock` owns the handlers and flags. It is only ever held for a
///   plain read or write, never across a call out.
///
/// The results observer takes `stateLock` only. That split is the point:
/// `analyze` may call the observer before it returns (Apple documents that it
/// can call it "zero times, one time, or many times", and that it may block
/// for backpressure), and with one lock for both the observer waited forever
/// on a lock the tap thread already held -- the tap stopped delivering, the
/// night stopped being monitored, and Stop then hung the main thread on the
/// same lock.
final class SoundEventClassifier: NSObject, SNResultsObserving, @unchecked Sendable {

    /// Below this, a classification is more likely background noise than a
    /// real event -- Apple's own examples for this taxonomy treat 0.5 as a
    /// reasonable floor.
    private static let confidenceFloor: Double = 0.5

    /// Categories worth surfacing on a sleeping person's own record of their
    /// own night. Deliberately narrow, and deliberately excludes "speech".
    private static let trackedIdentifiers: Set<String> = [
        "snoring", "cough", "coughing", "baby_cry_infant_cry", "baby_crying"
    ]

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "SoundEventClassifier")
    private let analysisLock = NSLock()
    private let stateLock = NSLock()

    // Guarded by `analysisLock`.
    private var analyzer: SNAudioStreamAnalyzer?
    /// The tap's frame position when this analyzer saw its first buffer.
    /// Positions are passed relative to it, so every analyzer's clock starts
    /// at zero -- which is what `SoundAnalysisEpoch` assumes when it maps a
    /// result back onto the session. A classifier restarted while the engine
    /// keeps running would otherwise report results hours late.
    private var frameOrigin: AVAudioFramePosition?

    // Guarded by `stateLock`.
    private var onEvent: (@Sendable (String, Double, TimeInterval, TimeInterval) -> Void)?
    private var onFailure: (@Sendable () -> Void)?
    private var _isAvailable = true
    private var _hasFailed = false
    private var _knownClassifications: Set<String> = []

    /// `false` once construction fails to build the request -- guards
    /// against a future OS ever retiring `.version1` rather than force-trying
    /// into a crash.
    var isAvailable: Bool { stateLock.withLock { _isAvailable } }
    /// `true` once the running request has failed. SoundAnalysis stops
    /// processing a request for good after an error (on iOS 18 the built-in
    /// classifier can fail this way once the phone locks), so nothing more
    /// will be classified until `start` builds a new one.
    var hasFailed: Bool { stateLock.withLock { _hasFailed } }
    var knownClassifications: Set<String> { stateLock.withLock { _knownClassifications } }
    var supportsSnoring: Bool { knownClassifications.contains("snoring") }

    /// - Parameter onFailure: called once, on SoundAnalysis's thread, if the
    ///   request fails after starting. Hop to the main actor before touching UI
    ///   state.
    func start(
        format: AVAudioFormat,
        onEvent: @escaping @Sendable (String, Double, TimeInterval, TimeInterval) -> Void,
        onFailure: (@Sendable () -> Void)? = nil
    ) {
        let newAnalyzer = SNAudioStreamAnalyzer(format: format)
        var known: Set<String> = []
        var added = false
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            known = Set(request.knownClassifications.map { "\($0)" })
            if !known.contains("snoring") {
                logger.error("version1 taxonomy has no snoring class; heuristic is the fallback")
            }
            try newAnalyzer.add(request, withObserver: self)
            added = true
        } catch {
            logger.error("Could not start sound classification: \(error.localizedDescription, privacy: .public)")
        }
        // Handlers first, so a result produced by the very first buffer finds
        // them in place.
        stateLock.withLock {
            self.onEvent = onEvent
            self.onFailure = onFailure
            _knownClassifications = known
            _isAvailable = added
            _hasFailed = false
        }
        analysisLock.withLock {
            analyzer?.removeAllRequests()
            analyzer = added ? newAnalyzer : nil
            frameOrigin = nil
        }
    }

    /// Called from the same audio-tap callback `SnoreDetector` already runs
    /// its heuristic from, not hopped to another queue first: `analyze`
    /// expects buffers in non-decreasing frame-position order, and the tap
    /// callback is already the one place that order is guaranteed.
    ///
    /// `analysisLock` is held across `analyze` so `stop()` cannot remove the
    /// requests from under a buffer being analysed; the main actor only
    /// contends for it when capture starts or stops, and the results observer
    /// never takes it.
    func process(_ buffer: AVAudioPCMBuffer, atFramePosition framePosition: AVAudioFramePosition) {
        analysisLock.withLock {
            guard let analyzer else { return }
            let origin = frameOrigin ?? framePosition
            frameOrigin = origin
            analyzer.analyze(buffer, atAudioFramePosition: max(0, framePosition - origin))
        }
    }

    func stop() {
        analysisLock.withLock {
            analyzer?.removeAllRequests()
            analyzer = nil
            frameOrigin = nil
        }
        stateLock.withLock {
            onEvent = nil
            onFailure = nil
        }
    }

    // MARK: - SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = result.timeRange.start.seconds
        let duration = result.timeRange.duration.seconds
        // Read under `stateLock`, called outside it: the handler may take its
        // own locks, and a stopped classifier has a nil handler. Never
        // `analysisLock` here -- see the type's doc comment.
        guard let onEvent = stateLock.withLock({ self.onEvent }) else { return }
        for classification in result.classifications {
            guard Self.trackedIdentifiers.contains(classification.identifier),
                  classification.confidence >= Self.confidenceFloor else { continue }
            onEvent(classification.identifier, classification.confidence, start, duration)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        logger.error("Sound classification failed: \(error.localizedDescription, privacy: .public)")
        // Report once. The request is finished; the owner decides when to
        // build a new one.
        let handler: (@Sendable () -> Void)? = stateLock.withLock {
            guard !_hasFailed else { return nil }
            _hasFailed = true
            return onFailure
        }
        handler?()
    }

    func requestDidComplete(_ request: SNRequest) {}
}
