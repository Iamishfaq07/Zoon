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
/// confidence) pairs, handed back through `onEvent`, survive past the
/// buffer they were measured in.
final class SoundEventClassifier: NSObject, SNResultsObserving, @unchecked Sendable {

    /// Below this, a classification is more likely background noise than a
    /// real event -- Apple's own examples for this taxonomy treat 0.5 as a
    /// reasonable floor.
    private static let confidenceFloor: Double = 0.5

    /// Categories worth surfacing on a sleeping person's own record of their
    /// own night. Deliberately narrow, and deliberately excludes "speech":
    /// the full taxonomy recognizes hundreds of everyday sounds (traffic,
    /// typing, music) that are just noise in a bedroom context, but speech
    /// specifically is excluded on privacy grounds, not just relevance --
    /// logging "talking detected at 2:14 AM" captures a partner or
    /// roommate's voice and presence without their consent, which is exactly
    /// what this feature's own privacy design (see `SnoreDetector`) commits
    /// to never doing, even in the derived, audio-free form an event is
    /// stored in.
    private static let trackedIdentifiers: Set<String> = [
        "snoring", "cough", "coughing", "baby_cry_infant_cry", "baby_crying"
    ]

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "SoundEventClassifier")
    private var analyzer: SNAudioStreamAnalyzer?
    private var onEvent: (@Sendable (String, Double) -> Void)?

    /// `false` once construction fails to build the request -- guards
    /// against a future OS ever retiring `.version1` rather than force-trying
    /// into a crash.
    private(set) var isAvailable = true

    func start(format: AVAudioFormat, onEvent: @escaping @Sendable (String, Double) -> Void) {
        self.onEvent = onEvent
        let newAnalyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try newAnalyzer.add(request, withObserver: self)
            analyzer = newAnalyzer
            isAvailable = true
        } catch {
            logger.error("Could not start sound classification: \(error.localizedDescription, privacy: .public)")
            isAvailable = false
        }
    }

    /// Called from the same audio-tap callback `SnoreDetector` already runs
    /// its heuristic from, not hopped to another queue first: `analyze`
    /// expects buffers in non-decreasing frame-position order, and the tap
    /// callback is already the one place that order is guaranteed.
    func process(_ buffer: AVAudioPCMBuffer, atFramePosition framePosition: AVAudioFramePosition) {
        analyzer?.analyze(buffer, atAudioFramePosition: framePosition)
    }

    func stop() {
        analyzer?.removeAllRequests()
        analyzer = nil
        onEvent = nil
    }

    // MARK: - SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        for classification in result.classifications {
            guard Self.trackedIdentifiers.contains(classification.identifier),
                  classification.confidence >= Self.confidenceFloor else { continue }
            onEvent?(classification.identifier, classification.confidence)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        logger.error("Sound classification failed: \(error.localizedDescription, privacy: .public)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
