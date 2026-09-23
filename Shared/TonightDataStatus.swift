import Foundation

/// The one line under Tonight that says what the plan is built on: when
/// Health data last arrived and where last night's sleep came from.
///
/// Absence is stated, not hidden. No refresh yet reads "not synced yet"
/// rather than showing nothing, and a night with no recorded source says
/// the source is unknown -- a plan can look confident on stale or
/// unattributed data, and this is where that shows.
enum TonightDataStatus {
    static func line(lastSync: Date?, sourceName: String?, now: Date) -> String {
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
        let source = trimmed.isEmpty ? "last night's source unknown" : "last night from \(trimmed)"
        return "\(sync) · \(source)"
    }
}
