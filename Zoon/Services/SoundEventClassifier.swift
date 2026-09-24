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
/// audio tap's thread, and result callbacks on SoundAnalysis's. Every piece of
/// mutable state is read and written under `lock`, which is what the
/// `@unchecked Sendable` below is claiming. It used to claim it without one:
/// `stop()` could clear `analyzer` and `onEvent` while the tap was mid-call.
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
    private let lock = NSLock()
    private var analyzer: SNAudioStreamAnalyzer?
    private var onEvent: (@Sendable (String, Double, TimeInterval, TimeInterval) -> Void)?
    private var _isAvailable = true
    private var _knownClassifications: Set<String> = []

    /// `false` once construction fails to build the request -- guards
    /// against a future OS ever retiring `.version1` rather than force-trying
    /// into a crash.
    var isAvailable: Bool { lock.withLock { _isAvailable } }
    var knownClassifications: Set<String> { lock.withLock { _knownClassifications } }
    var supportsSnoring: Bool { knownClassifications.contains("snoring") }

    func start(format: AVAudioFormat, onEvent: @escaping @Sendable (String, Double, TimeInterval, TimeInterval) -> Void) {
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
        lock.withLock {
            self.onEvent = onEvent
            _knownClassifications = known
            _isAvailable = added
            if added { analyzer = newAnalyzer }
        }
    }

    /// Called from the same audio-tap callback `SnoreDetector` already runs
    /// its heuristic from, not hopped to another queue first: `analyze`
    /// expects buffers in non-decreasing frame-position order, and the tap
    /// callback is already the one place that order is guaranteed.
    ///
    /// The lock is held across `analyze` so `stop()` cannot remove the
    /// requests from under a buffer being analysed; the main actor only
    /// contends for it when capture starts or stops.
    func process(_ buffer: AVAudioPCMBuffer, atFramePosition framePosition: AVAudioFramePosition) {
        lock.withLock {
            analyzer?.analyze(buffer, atAudioFramePosition: framePosition)
        }
    }

    func stop() {
        lock.withLock {
            analyzer?.removeAllRequests()
            analyzer = nil
            onEvent = nil
        }
    }

    // MARK: - SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = result.timeRange.start.seconds
        let duration = result.timeRange.duration.seconds
        // Read under the lock, called outside it: the handler may take its
        // own locks, and a stopped classifier has a nil handler.
        guard let onEvent = lock.withLock({ self.onEvent }) else { return }
        for classification in result.classifications {
            guard Self.trackedIdentifiers.contains(classification.identifier),
                  classification.confidence >= Self.confidenceFloor else { continue }
            onEvent(classification.identifier, classification.confidence, start, duration)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        logger.error("Sound classification failed: \(error.localizedDescription, privacy: .public)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
