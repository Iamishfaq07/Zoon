import Foundation

/// One SoundAnalysis window that claimed snoring.
struct SnoreClassificationWindow: Equatable, Sendable, Codable {
    /// Session-relative start, from the classifier `timeRange`, not `Date.now`.
    let start: TimeInterval
    let duration: TimeInterval
    let confidence: Double
    let identifier: String
}

enum SnoreMonitoringConfidence: String, Sendable, Equatable, Codable {
    case high
    case moderate
    case limited

    var label: String {
        switch self {
        case .high: "Strong"
        case .moderate: "Moderate"
        case .limited: "Limited"
        }
    }

    var accessibilityName: String { "Monitoring quality \(label.lowercased())" }
}

/// Turns overlapping classifier windows into snore seconds.
///
/// Apple's classifier can fire on every analysis hop. Counting each hop as
/// a snore minute is wrong; ignoring them (and only using the heuristic)
/// is how a session could recognise snoring and still report 0 minutes.
enum SnoreEpisodeAggregator: Sendable {

    static let snoringIdentifiers: Set<String> = ["snoring", "snore"]
    static let confidenceFloor: Double = 0.5
    /// Merge windows that touch or overlap within this slack.
    static let mergeSlack: TimeInterval = 1.5

    static func snoreSeconds(
        from windows: [SnoreClassificationWindow],
        threshold: Double = confidenceFloor
    ) -> Double {
        mergedIntervals(from: windows, threshold: threshold)
            .reduce(0) { $0 + ($1.end - $1.start) }
    }

    static func mergedIntervals(
        from windows: [SnoreClassificationWindow],
        threshold: Double = confidenceFloor
    ) -> [(start: TimeInterval, end: TimeInterval, confidence: Double)] {
        let eligible = windows
            .filter { snoringIdentifiers.contains($0.identifier.lowercased()) && $0.confidence >= threshold }
            .map { (start: $0.start, end: $0.start + max(0, $0.duration), confidence: $0.confidence) }
            .sorted { $0.start < $1.start }
        guard var current = eligible.first else { return [] }
        var out: [(start: TimeInterval, end: TimeInterval, confidence: Double)] = []
        for next in eligible.dropFirst() {
            if next.start <= current.end + mergeSlack {
                current.end = max(current.end, next.end)
                current.confidence = max(current.confidence, next.confidence)
            } else {
                out.append(current)
                current = next
            }
        }
        out.append(current)
        return out
    }

    static func confidence(
        classifierAvailable: Bool,
        classifierSupportsSnoring: Bool,
        monitoredSeconds: Double,
        lastBufferAge: TimeInterval?,
        heuristicSeconds: Double,
        classifierSeconds: Double,
        sessionEnded: Bool = false,
        interruptionDuration: TimeInterval = 0
    ) -> SnoreMonitoringConfidence {
        // After stop, lastBufferAge grows forever. Do not let a strong
        // completed night read as Limited because the mic is now quiet.
        let buffersFlowing = sessionEnded || (lastBufferAge ?? .infinity) < 2
        let longEnough = monitoredSeconds >= 30 * 60
        let bothAgree = classifierSeconds >= 1 && heuristicSeconds >= 1
        let coverageOK = interruptionDuration < monitoredSeconds * 0.25
        if classifierAvailable, classifierSupportsSnoring, buffersFlowing, longEnough, bothAgree, coverageOK {
            return .high
        }
        if (buffersFlowing || sessionEnded), monitoredSeconds >= 10 * 60, classifierAvailable || heuristicSeconds >= 1 {
            return .moderate
        }
        return .limited
    }
}
