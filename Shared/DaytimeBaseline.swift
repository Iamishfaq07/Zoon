import Foundation

/// What *your* waking physiology usually looks like at this hour of the day.
///
/// **The bug this exists for.** Physiological Load compares today's waking
/// heart rate and HRV against `RollingBaseline`'s overnight figures. Autonomic
/// tone during sleep is not the same physiological state as calm wakefulness:
/// a resting heart rate of 54 asleep and 70 sat at a desk are both perfectly
/// normal for the same person, but the second is +30% against the first, which
/// the ±20% band reads as "High". A relaxed afternoon could therefore report as
/// elevated load purely because the two numbers do not live on the same scale.
/// `StressScore`'s own doc comment has named this as the reason it is labelled
/// Experimental; this is the baseline it asked for.
///
/// **Why binned by time of day.** Waking physiology is not flat across a day.
/// Heart rate runs lowest in the early morning and highest in the late
/// afternoon, by more than the margin the load bands care about, so one
/// all-day average would make every morning look calm and every afternoon
/// look stressed. Three-hour blocks are coarse enough that ordinary daily
/// variation fills them and fine enough to separate those two.
///
/// **What the caller must supply.** Quiet samples only. Workouts, the window
/// after them, and hours with high movement are exercise, not autonomic load,
/// and a baseline that includes them is biased upward -- which is the
/// dangerous direction, because an inflated baseline makes genuinely elevated
/// readings look normal. `SleepDataCoordinator` already builds exactly those
/// quiet intervals for today's reading and reuses the same rule here, so both
/// sides of the comparison are the same quantity.
struct DaytimeBaseline: Codable, Hashable, Sendable {

    struct Sample: Hashable, Sendable {
        let date: Date
        let value: Double

        init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    struct Bin: Codable, Hashable, Sendable {
        /// 0...7, each covering `binHours` hours from midnight.
        let index: Int
        /// Robust centre. Median rather than mean: daytime readings are
        /// skewed by the activity that survives the quiet filter, and a mean
        /// follows that tail while a median does not.
        let median: Double
        /// Median absolute deviation -- the robust counterpart of the centre
        /// above, for a caller that wants a band rather than a point.
        let spread: Double
        let sampleCount: Int
        /// Distinct calendar days contributing. Counted separately from
        /// samples because twelve readings from one unusual day is not a
        /// week's worth of evidence, and only the day count can tell them
        /// apart.
        let dayCount: Int
    }

    /// Hours per block. Eight blocks a day.
    static let binHours = 3
    static let binCount = 24 / binHours

    /// Samples a block needs before its centre is worth comparing against.
    static let minimumSamplesPerBin = 12
    /// Distinct days a block needs. A week, so one atypical day -- a flight,
    /// a fever, a deadline -- cannot define what "usual" means at that hour.
    static let minimumDaysPerBin = 7

    /// Days of history to build from.
    static let windowDays = 14

    let bins: [Bin]

    static func binIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let hour = calendar.component(.hour, from: date)
        return min(binCount - 1, hour / binHours)
    }

    /// The block covering `date`, or `nil` when it has not earned the right
    /// to be compared against yet.
    func bin(for date: Date, calendar: Calendar = .current) -> Bin? {
        let index = Self.binIndex(for: date, calendar: calendar)
        return bins.first { $0.index == index }
    }

    var isEmpty: Bool { bins.isEmpty }

    /// Builds the baseline, keeping only blocks that clear both thresholds.
    ///
    /// A block that does not clear them is dropped rather than included with
    /// a caveat: this value's whole purpose is to be the thing another number
    /// is measured against, and a centre drawn from four readings on two days
    /// would move the score around more than the physiology does.
    static func build(samples: [Sample], calendar: Calendar = .current) -> DaytimeBaseline {
        var grouped: [Int: [Sample]] = [:]
        for sample in samples {
            grouped[binIndex(for: sample.date, calendar: calendar), default: []].append(sample)
        }

        let bins: [Bin] = grouped.compactMap { index, samples in
            let days = Set(samples.map { calendar.startOfDay(for: $0.date) })
            guard samples.count >= minimumSamplesPerBin, days.count >= minimumDaysPerBin
            else { return nil }

            let values = samples.map(\.value)
            guard let median = Statistics.median(values) else { return nil }
            return Bin(
                index: index,
                median: median,
                spread: Statistics.medianAbsoluteDeviation(values, median: median) ?? 0,
                sampleCount: samples.count,
                dayCount: days.count
            )
        }

        return DaytimeBaseline(bins: bins.sorted { $0.index < $1.index })
    }
}
