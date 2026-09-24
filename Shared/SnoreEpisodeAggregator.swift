import Foundation

/// One SoundAnalysis window that claimed snoring.
struct SnoreClassificationWindow: Equatable, Sendable, Codable {
    /// Session-relative start, from the classifier `timeRange`, not `Date.now`.
    let start: TimeInterval
    let duration: TimeInterval
    let confidence: Double
    let identifier: String
}

enum SnoreMonitoringConfidence: String, Sendable, Equatable, Codable, Comparable {
    case high
    case moderate
    case limited

    private var rank: Int {
        switch self {
        case .limited: 0
        case .moderate: 1
        case .high: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

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

    /// The confidence a session's *result* deserves: the weaker of how much
    /// the detector can be trusted and how much of the night it covered.
    ///
    /// Audit §8: this used to be detector confidence alone. Thirty minutes
    /// of a classifier and heuristic agreeing read as `.high` even when the
    /// person slept eight hours -- a strong detector on a sliver of the night
    /// is not a strong night result.
    static func confidence(
        classifierAvailable: Bool,
        classifierSupportsSnoring: Bool,
        monitoredSeconds: Double,
        lastBufferAge: TimeInterval?,
        heuristicSeconds: Double,
        classifierSeconds: Double,
        sessionEnded: Bool = false,
        interruptionDuration: TimeInterval = 0,
        intendedWindowSeconds: TimeInterval = SnoreCoverage.defaultIntendedWindowSeconds
    ) -> SnoreMonitoringConfidence {
        breakdown(
            classifierAvailable: classifierAvailable,
            classifierSupportsSnoring: classifierSupportsSnoring,
            monitoredSeconds: monitoredSeconds,
            lastBufferAge: lastBufferAge,
            heuristicSeconds: heuristicSeconds,
            classifierSeconds: classifierSeconds,
            sessionEnded: sessionEnded,
            interruptionDuration: interruptionDuration,
            intendedWindowSeconds: intendedWindowSeconds
        ).final
    }

    static func breakdown(
        classifierAvailable: Bool,
        classifierSupportsSnoring: Bool,
        monitoredSeconds: Double,
        lastBufferAge: TimeInterval?,
        heuristicSeconds: Double,
        classifierSeconds: Double,
        sessionEnded: Bool = false,
        interruptionDuration: TimeInterval = 0,
        intendedWindowSeconds: TimeInterval = SnoreCoverage.defaultIntendedWindowSeconds
    ) -> SnoreConfidenceBreakdown {
        let detector = detectorConfidence(
            classifierAvailable: classifierAvailable,
            classifierSupportsSnoring: classifierSupportsSnoring,
            monitoredSeconds: monitoredSeconds,
            lastBufferAge: lastBufferAge,
            heuristicSeconds: heuristicSeconds,
            classifierSeconds: classifierSeconds,
            sessionEnded: sessionEnded
        )
        let coverage = SnoreCoverage(
            monitoredSeconds: monitoredSeconds,
            interruptionSeconds: interruptionDuration,
            intendedWindowSeconds: intendedWindowSeconds
        )
        return SnoreConfidenceBreakdown(detector: detector, coverage: coverage)
    }

    /// Whether the detector's output can be believed: classifier present and
    /// supporting snoring, audio actually arriving, and the classifier and
    /// the loudness heuristic telling the same story.
    ///
    /// Agreement is two-sided. Both finding snoring agrees; both finding
    /// none agrees too -- a quiet night is not a weaker detector. One firing
    /// while the other stays silent is the disagreement.
    static func detectorConfidence(
        classifierAvailable: Bool,
        classifierSupportsSnoring: Bool,
        monitoredSeconds: Double,
        lastBufferAge: TimeInterval?,
        heuristicSeconds: Double,
        classifierSeconds: Double,
        sessionEnded: Bool = false
    ) -> SnoreMonitoringConfidence {
        // After stop, lastBufferAge grows forever. Do not let a strong
        // completed night read as Limited because the mic is now quiet.
        let buffersFlowing = sessionEnded || (lastBufferAge ?? .infinity) < 2
        let classifierHeard = classifierSeconds >= 1
        let heuristicHeard = heuristicSeconds >= 1
        let agree = classifierHeard == heuristicHeard
        if classifierAvailable, classifierSupportsSnoring, buffersFlowing, agree, monitoredSeconds >= 10 * 60 {
            return .high
        }
        if buffersFlowing, monitoredSeconds >= 10 * 60, classifierAvailable || heuristicHeard {
            return .moderate
        }
        return .limited
    }
}

/// How much of the night a Snore Check session actually heard.
///
/// Engineering thresholds, documented as such rather than presented as
/// science: they are a starting point to calibrate against real sessions.
struct SnoreCoverage: Equatable, Sendable {
    /// Used when nothing better is known about tonight's sleep window.
    static let defaultIntendedWindowSeconds: TimeInterval = 8 * 3600
    /// "Strong" coverage: this share of the intended window...
    static let highCoverageRatio = 0.75
    /// ...and at least this much monitored time in absolute terms.
    static let highCoverageMinimumSeconds: TimeInterval = 4 * 3600
    /// "Moderate" coverage.
    static let moderateCoverageRatio = 0.35
    static let moderateCoverageMinimumSeconds: TimeInterval = 60 * 60
    /// Interruptions longer than this share of the session cap coverage at
    /// moderate; longer than twice it, at limited.
    static let interruptionShareCap = 0.25

    let monitoredSeconds: TimeInterval
    let interruptionSeconds: TimeInterval
    let intendedWindowSeconds: TimeInterval

    /// Monitored time over the intended window, 0...1.
    var ratio: Double {
        guard intendedWindowSeconds > 0 else { return 0 }
        return min(1, max(0, monitoredSeconds) / intendedWindowSeconds)
    }

    /// Interruptions as a share of the whole session, heard or not.
    var interruptionShare: Double {
        let session = monitoredSeconds + interruptionSeconds
        guard session > 0 else { return 0 }
        return interruptionSeconds / session
    }

    var confidence: SnoreMonitoringConfidence {
        var level: SnoreMonitoringConfidence
        if ratio >= Self.highCoverageRatio, monitoredSeconds >= Self.highCoverageMinimumSeconds {
            level = .high
        } else if ratio >= Self.moderateCoverageRatio, monitoredSeconds >= Self.moderateCoverageMinimumSeconds {
            level = .moderate
        } else {
            level = .limited
        }
        if interruptionShare >= Self.interruptionShareCap * 2 {
            level = min(level, .limited)
        } else if interruptionShare >= Self.interruptionShareCap {
            level = min(level, .moderate)
        }
        return level
    }
}

/// Detector and coverage kept apart, so a screen can say which one limited
/// the result.
struct SnoreConfidenceBreakdown: Equatable, Sendable {
    let detector: SnoreMonitoringConfidence
    let coverage: SnoreCoverage

    /// Bounded by the weaker of the two.
    var final: SnoreMonitoringConfidence { min(detector, coverage.confidence) }

    var coveragePercent: Int { Int((coverage.ratio * 100).rounded()) }

    /// What a session's result may say. A session that heard no snoring on
    /// too little of the night has not shown that there was none.
    func resultSentence(snoreMinutes: Double) -> String {
        if snoreMinutes < 1 {
            return coverage.confidence == .limited
                ? "No conclusion — only \(coveragePercent)% of the night was monitored, which is not enough to say there was no snoring."
                : "No snoring flagged in the \(coveragePercent)% of the night that was monitored."
        }
        return "Snoring flagged in the \(coveragePercent)% of the night that was monitored. Snoring on its own is not a medical finding."
    }
}
