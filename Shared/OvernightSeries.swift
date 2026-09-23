import Foundation

/// A physiological series restricted to the night it is drawn over.
///
/// **The defect this exists for.** The hypnogram's Heart overlay was handed
/// `DayContext.hourlyHeartRate` -- the *daytime* series, queried from wake to
/// now for the body battery. None of it fell inside the night, so the overlay
/// could be switched on, report itself available because the array had two
/// points, and draw nothing; and the scrub readout could quote a 09:00 heart
/// rate against a 03:00 stage. The night now gets its own series, and every
/// consumer clips to the night and counts only what is inside it.
enum OvernightSeries {

    /// Samples inside `night`, finite and positive, in time order.
    static func clipped(
        _ samples: [(date: Date, bpm: Double)],
        to night: DateInterval
    ) -> [(date: Date, bpm: Double)] {
        samples
            .filter { night.contains($0.date) && $0.bpm.isFinite && $0.bpm > 0 }
            .sorted { $0.date < $1.date }
    }

    /// Whether there is a line to draw: two points inside the night.
    static func isPlottable(_ samples: [(date: Date, bpm: Double)], over night: DateInterval) -> Bool {
        clipped(samples, to: night).count >= 2
    }

    /// The sample nearest `time`, within `tolerance`, from inside the night
    /// only. A point outside the night is never the answer, however near.
    static func nearest(
        to time: Date,
        in samples: [(date: Date, bpm: Double)],
        over night: DateInterval,
        tolerance: TimeInterval = 30 * 60
    ) -> Double? {
        clipped(samples, to: night)
            .filter { abs($0.date.timeIntervalSince(time)) <= tolerance }
            .min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }?
            .bpm
    }
}
