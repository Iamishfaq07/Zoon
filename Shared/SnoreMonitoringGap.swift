import Foundation

/// A period when Snore Check was not actually listening.
///
/// Counted interruptions (`2 gaps`) are not a timeline. These intervals
/// keep wall-clock holes — a 20-minute call, a 3-minute alarm — so the
/// session view can show coverage instead of pretending the night was
/// continuous. Derived only: no audio.
struct SnoreMonitoringGap: Codable, Equatable, Sendable, Identifiable {
    var startedAt: Date
    var endedAt: Date?

    var id: Date { startedAt }

    var duration: TimeInterval {
        (endedAt ?? startedAt).timeIntervalSince(startedAt)
    }
}
