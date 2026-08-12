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
enum MetricConfidence: String, Codable, Sendable {
    case insufficient, low, moderate, high

    var label: String {
        switch self {
        case .insufficient: "Insufficient data"
        case .low: "Low confidence"
        case .moderate: "Moderate confidence"
        case .high: "High confidence"
        }
    }
}
