import Foundation

/// The one line under Tonight that says what the plan is built on: when
/// Health data last arrived and where last night's sleep came from.
///
/// Absence is stated, not hidden. No refresh yet reads "not synced yet"
/// rather than showing nothing, and a night with no recorded source says
/// the source is unknown -- a plan can look confident on stale or
/// unattributed data, and this is where that shows.
enum TonightDataStatus {
    /// How much of last night's sleep came with stages: all of it, part of
    /// it, or none (a duration-only source). `nil` when there is no sleep
    /// to describe. Says whether the stage figures elsewhere were measured.
    static func stageCoverage(stagedMinutes: Double, unstagedMinutes: Double) -> String? {
        let staged = max(0, stagedMinutes)
        let total = staged + max(0, unstagedMinutes)
        guard total > 0 else { return nil }
        guard staged > 0 else { return "duration only, no stages" }
        let percent = Int((staged / total * 100).rounded(.down))
        return percent >= 95 ? "staged" : "staged for \(percent)% of it"
    }

    static func line(
        lastSync: Date?,
        sourceName: String?,
        now: Date,
        stagedMinutes: Double = 0,
        unstagedMinutes: Double = 0
    ) -> String {
        let sync: String
        if let lastSync {
            let minutes = max(0, now.timeIntervalSince(lastSync)) / 60
            switch minutes {
            case ..<1: sync = "Health synced just now"
            case ..<60: sync = "Health synced \(Int(minutes))m ago"
            case ..<(24 * 60): sync = "Health synced \(Int(minutes / 60))h ago"
            default: sync = "Health last synced over a day ago"
            }
        } else {
            sync = "Health not synced yet"
        }
        let trimmed = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var source = trimmed.isEmpty ? "last night's source unknown" : "last night from \(trimmed)"
        if let coverage = stageCoverage(stagedMinutes: stagedMinutes, unstagedMinutes: unstagedMinutes) {
            source += ", \(coverage)"
        }
        return "\(sync) · \(source)"
    }
}
