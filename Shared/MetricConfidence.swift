import Foundation

/// Shared confidence banding for any metric whose accuracy depends on how
/// much history has accumulated behind it.
///
/// Pulled out because `LearnedSleepNeed` and `SleepIntelligenceScore` had each
/// independently defined an identical `insufficient/low/moderate/high` enum
/// with its own near-duplicate label text -- the same four-band judgment
/// re-invented twice, with no guarantee the two stayed in sync. Every metric
/// still picks its own thresholds for what counts as "moderate" versus
/// "high" (a night count is not a completeness percentage); only the bands
/// and their labels are shared.
enum MetricConfidence: String, Codable, Sendable, Comparable {
    case insufficient, low, moderate, high

    /// Ordered so callers can take the weaker of two independent judgments
    /// -- `SleepMap` bounds a finding by both how deep the winning region is
    /// and how many regions it beat, and the honest answer is the lower of
    /// the two, not their average.
    private var rank: Int {
        switch self {
        case .insufficient: 0
        case .low: 1
        case .moderate: 2
        case .high: 3
        }
    }

    static func < (lhs: MetricConfidence, rhs: MetricConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    var label: String {
        switch self {
        case .insufficient: "Insufficient data"
        case .low: "Low confidence"
        case .moderate: "Moderate confidence"
        case .high: "High confidence"
        }
    }
}
