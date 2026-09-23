import Foundation

/// The window a pinch on the night chart leaves behind.
///
/// Kept apart from the view so the arithmetic is testable: a pinch out by
/// `magnification` shows `1 / magnification` of the current window, centred
/// where the fingers were, never narrower than `minimumDuration` and never
/// outside the night. A window that grows back to (nearly) the whole night
/// returns `nil`, which the chart already reads as "not zoomed".
enum ChartZoom {
    /// Thirty minutes: narrow enough to read a short awakening, wide enough
    /// that a 30-second stage block is still a visible mark.
    static let minimumDuration: TimeInterval = 30 * 60

    static func window(
        current: DateInterval,
        full: DateInterval,
        magnification: Double,
        anchorFraction: Double,
        minimumDuration: TimeInterval = ChartZoom.minimumDuration
    ) -> DateInterval? {
        guard full.duration > 0, magnification.isFinite, magnification > 0 else { return current == full ? nil : current }
        let floor = min(minimumDuration, full.duration)
        let duration = min(full.duration, max(floor, current.duration / magnification))
        // Within 5% of the whole night reads as the whole night; a pinch
        // back out should not leave the chart a few minutes short of it.
        if duration >= full.duration * 0.95 { return nil }

        let anchor = min(1, max(0, anchorFraction.isFinite ? anchorFraction : 0.5))
        let anchorTime = current.start.addingTimeInterval(current.duration * anchor)
        // Keep the moment under the fingers at the same place on screen.
        var start = anchorTime.addingTimeInterval(-duration * anchor)
        start = max(full.start, min(start, full.end.addingTimeInterval(-duration)))
        return DateInterval(start: start, duration: duration)
    }
}
