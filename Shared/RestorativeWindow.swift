import Foundation

/// Stretches of the waking day where this person's physiology looked settled
/// *for them, at that hour*.
///
/// **What this is not.** It is not meditation detection, and it does not know
/// anything about how anyone felt. A low heart rate at a desk and a low heart
/// rate on a sofa are the same reading; a settled autonomic state is not a
/// calm mind, and the brief is explicit that the copy must not imply one.
/// Every sentence this type produces says what was measured — heart rate
/// relative to this person's own usual figure at this hour — and stops there.
///
/// **Why it needs `DaytimeBaseline` and refuses without it.** Waking heart
/// rate is not flat across a day: it runs lowest in the early morning and
/// highest in the late afternoon, by more than the margin that separates
/// "settled" from "ordinary". A fixed bpm threshold would therefore mark most
/// of every morning and none of any evening, which is a clock reading, not a
/// physiological one. `DaytimeBaseline` already holds the per-person,
/// per-three-hour-block median and MAD, built from quiet samples only, and
/// already refuses to publish a block until it has twelve samples across seven
/// distinct days. This type inherits that refusal: no qualifying block, no
/// window. Missing data is not normal.
///
/// **What gates a window** — all three, as the brief requires:
/// - movement is low (`quietKcalPerBin`, scaled from the same
///   150 kcal/hour figure `SleepDataCoordinator` uses to exclude
///   high-movement hours from the baseline itself, so both sides of the
///   comparison exclude the same thing),
/// - coverage is sufficient (`minimumCoverage` of the bins in the run carry a
///   real heart-rate reading; absent bins are never filled in),
/// - heart rate is favourable against the *comparable* personal baseline
///   (`settledZ` below the block's own median, in units of the block's own
///   spread).
///
/// **HRV corroborates and never gates.** HealthKit holds a handful of SDNN
/// readings on an ordinary day, so at five-minute resolution most bins have
/// none. A gate on HRV would therefore reject almost every genuine window for
/// want of a reading that was never going to exist. Where HRV is present it is
/// reported, and where it is absent the window says so rather than implying it
/// was checked.
enum RestorativeWindow {

    /// One fixed-width bin of the day. `value` is absent where the metric had
    /// no coverage — never zero, which for a heart rate would read as the
    /// calmest possible bin.
    struct Sample: Hashable, Sendable {
        let date: Date
        let value: Double?

        init(date: Date, value: Double?) {
            self.date = date
            self.value = value
        }
    }

    /// Bin width. Five minutes is the finest resolution worth asking
    /// HealthKit for: `HKStatisticsCollectionQuery` buckets in its own store
    /// so the cost is the same, and anything finer turns a single noisy
    /// sample into its own bin.
    static let binMinutes = 5

    /// A run shorter than this is a quiet minute, not a window. Fifteen
    /// minutes is three bins, which is also the fewest readings that can
    /// establish a direction rather than a point.
    static let minimumMinutes = 15

    /// How far below the block's own median a bin must sit, in units of that
    /// block's own median absolute deviation, scaled the way `Statistics`
    /// scales a robust z. Half a robust z is deliberately modest: the claim
    /// is "lower than your usual figure at this hour", not "remarkable".
    static let settledZ = -0.5

    /// Active energy per bin that still counts as low movement. 150 kcal/hour
    /// is the figure `SleepDataCoordinator` already uses to strike an hour out
    /// of the baseline; a bin is that, pro rata.
    static let quietKcalPerBin = 150.0 * Double(binMinutes) / 60.0

    /// Fraction of a run's bins that must carry a heart-rate reading. Below
    /// this the run is a gap with two readings either side of it.
    static let minimumCoverage = 0.6

    /// A block's spread must be at least this wide before a z against it
    /// means anything. A degenerate MAD makes every reading extreme.
    static let minimumSpread = 0.5

    struct Window: Hashable, Sendable, Identifiable {
        let start: Date
        let end: Date
        /// Median heart rate across the bins that had one.
        let medianHeartRate: Double
        /// The personal figure it was compared against: the median of this
        /// person's own quiet readings in this three-hour block.
        let baselineHeartRate: Double
        /// Median HRV across the bins that had one, where any did.
        let medianHRV: Double?
        let coveredBins: Int
        let totalBins: Int

        var id: Date { start }
        var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
        var coverage: Double {
            totalBins == 0 ? 0 : Double(coveredBins) / Double(totalBins)
        }

        /// Beats below the personal figure for this hour, rounded the way it
        /// is printed.
        var beatsBelowBaseline: Int {
            Int((baselineHeartRate - medianHeartRate).rounded())
        }

        /// Coverage is the only thing graded here. The comparison itself is
        /// either against a qualifying block or it does not happen at all,
        /// so there is no weak-baseline tier to report.
        var confidence: MetricConfidence {
            if coverage >= 0.9 { return .high }
            if coverage >= 0.75 { return .moderate }
            return .low
        }

        /// The brief's wording, near enough verbatim, and nothing beyond it.
        /// No "calm", no "relaxed", no "meditation" — none of which is
        /// measured, and the first two of which are claims about a mind.
        var sentence: String {
            "Your physiology was relatively settled during this period."
        }

        /// What was actually measured, kept separate from the sentence so a
        /// caller can show one without the other.
        var evidence: String {
            let hrv = medianHRV.map { ", HRV \(Int($0.rounded())) ms" } ?? ""
            return "Heart rate \(Int(medianHeartRate.rounded())) bpm against your usual "
                + "\(Int(baselineHeartRate.rounded())) bpm at this hour\(hrv)."
        }

        /// Named only when absent, so a window never implies HRV was weighed
        /// when there was none to weigh.
        var hrvNote: String? {
            medianHRV == nil ? "No HRV readings in this window." : nil
        }
    }

    /// Finds every window in `heartRate`'s span.
    ///
    /// - Parameters:
    ///   - heartRate: fixed-width bins, ascending, gaps expressed as a `nil`
    ///     value rather than as a missing element where possible. Missing
    ///     elements are handled too: a bin absent from the array breaks the
    ///     run, because a run has to be contiguous in time to be a window.
    ///   - activeEnergy: the same bins for active energy. A bin with no entry
    ///     is treated as unknown movement and breaks the run — the gate is
    ///     "movement was low", and silence is not low.
    ///   - hrv: sparse; used only to describe a window that already qualified.
    ///   - baseline: this person's quiet waking heart rate by time of day.
    ///   - excluded: sleep, workouts and their buffer. Anything overlapping
    ///     one of these is not a waking quiet period at all.
    static func windows(
        heartRate: [Sample],
        activeEnergy: [Sample],
        hrv: [Sample] = [],
        baseline: DaytimeBaseline,
        excluded: [DateInterval] = [],
        calendar: Calendar = .current
    ) -> [Window] {

        guard !baseline.isEmpty, !heartRate.isEmpty else { return [] }

        let binSeconds = Double(binMinutes) * 60
        let energyByDate = Dictionary(
            activeEnergy.map { ($0.date, $0.value) }, uniquingKeysWith: { first, _ in first }
        )
        let hrvByDate = Dictionary(
            hrv.map { ($0.date, $0.value) }, uniquingKeysWith: { first, _ in first }
        )
        let sorted = heartRate.sorted { $0.date < $1.date }

        var windows: [Window] = []
        var run: [Sample] = []

        func flush() {
            defer { run = [] }
            // A run that ends only because its trailing bins had no readings
            // would carry those bins into both its span and its coverage, so
            // a window would read as longer and worse-covered than the settled
            // stretch it actually describes. Trim both ends back to a bin that
            // carried a reading.
            guard let lead = run.firstIndex(where: { $0.value != nil }),
                  let tail = run.lastIndex(where: { $0.value != nil })
            else { return }
            let bins = Array(run[lead...tail])
            guard let first = bins.first, let last = bins.last else { return }
            let start = first.date
            let end = last.date.addingTimeInterval(binSeconds)
            guard end.timeIntervalSince(start) >= Double(minimumMinutes) * 60 else { return }

            let values = bins.compactMap(\.value)
            let coverage = Double(values.count) / Double(bins.count)
            guard coverage >= minimumCoverage,
                  let median = Statistics.median(values),
                  // The block is re-read at the run's own midpoint rather
                  // than at its start: a run straddling a block boundary
                  // belongs to whichever block holds most of it, and using
                  // the start would compare an 18:05 reading against the
                  // afternoon.
                  let block = baseline.bin(
                      for: start.addingTimeInterval(end.timeIntervalSince(start) / 2),
                      calendar: calendar
                  )
            else { return }

            let hrvValues = bins.compactMap { hrvByDate[$0.date] ?? nil }

            windows.append(
                Window(
                    start: start,
                    end: end,
                    medianHeartRate: median,
                    baselineHeartRate: block.median,
                    medianHRV: Statistics.median(hrvValues),
                    coveredBins: values.count,
                    totalBins: bins.count
                )
            )
        }

        var expected: Date?

        for sample in sorted {
            // A jump in time ends the run whatever the readings say: two
            // settled stretches either side of an hour at the gym are two
            // windows, not one long one.
            if let expected, abs(sample.date.timeIntervalSince(expected)) > 1 {
                flush()
            }
            expected = sample.date.addingTimeInterval(binSeconds)

            let bin = DateInterval(start: sample.date, duration: binSeconds)
            let isExcluded = excluded.contains { $0.intersects(bin) }
            let movementIsLow = (energyByDate[sample.date] ?? nil).map { $0 <= quietKcalPerBin } ?? false

            guard !isExcluded, movementIsLow else {
                flush()
                continue
            }

            // A bin with no heart rate neither qualifies nor breaks the run:
            // a watch that missed one reading has not ended the period. The
            // coverage gate is what stops a run of them counting.
            guard let value = sample.value else {
                run.append(sample)
                continue
            }

            guard let block = baseline.bin(for: sample.date, calendar: calendar),
                  block.spread >= minimumSpread
            else {
                flush()
                continue
            }

            let z = 0.6745 * (value - block.median) / block.spread
            if z <= settledZ {
                run.append(sample)
            } else {
                flush()
            }
        }
        flush()

        return windows
    }

    /// The day's windows as one line, for a caller that wants a summary
    /// rather than a list. Returns `nil` rather than a sentence about zero,
    /// because "no settled windows today" is also what an empty HealthKit
    /// store looks like, and the two must not read the same.
    static func summary(_ windows: [Window]) -> String? {
        guard !windows.isEmpty else { return nil }
        let total = windows.reduce(0) { $0 + $1.minutes }
        return "\(windows.count.pluralized("settled period")) today, "
            + "\(total.pluralized("minute")) in total."
    }
}
