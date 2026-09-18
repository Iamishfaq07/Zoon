import Foundation

/// How completely each metric Zoon depends on has actually been showing up,
/// per metric, over a trailing window -- not a single blended "data
/// quality" number.
///
/// Every score in this app is only as trustworthy as its inputs. A missing
/// HRV reading degrades `SleepHealth`'s confidence band quietly; a missing
/// resting heart rate falls back to a proxy inside `RecoveryScore`. Those
/// fallbacks are individually documented at their call sites, but nowhere
/// does the app show, in one place, *which* metrics have actually been
/// reliable lately. This is that place: read-only, diagnostic, never fed
/// back into any score itself.
struct DataQuality {

    enum Metric: String, CaseIterable, Identifiable, Sendable {
        case sleep, heartRate, restingHeartRate, hrv, respiratoryRate, spo2, wristTemperature, breathing

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sleep: "Sleep"
            case .heartRate: "Heart rate"
            case .restingHeartRate: "Resting heart rate"
            case .hrv: "Heart rate variability"
            case .respiratoryRate: "Respiratory rate"
            case .spo2: "Blood oxygen"
            case .wristTemperature: "Wrist temperature"
            case .breathing: "Breathing disturbances"
            }
        }

        var symbol: String {
            switch self {
            case .sleep: "bed.double.fill"
            case .heartRate: "heart.fill"
            case .restingHeartRate: "heart.text.square.fill"
            case .hrv: "waveform.path.ecg"
            case .respiratoryRate: "lungs.fill"
            case .spo2: "drop.fill"
            case .wristTemperature: "thermometer"
            case .breathing: "wind"
            }
        }

        /// Whether `night` has a usable reading for this metric. `sleep`
        /// itself is always true for a night that exists at all -- its
        /// presence in the array *is* the measurement -- so it measures
        /// something different from the rest: how many of the expected
        /// nights in the window have a row at all, versus how many of
        /// those rows are missing a given secondary reading.
        fileprivate func isPresent(in night: SleepNightFeatures) -> Bool {
            switch self {
            case .sleep: true
            case .heartRate: night.avgHeartRate != nil
            case .restingHeartRate: night.restingHeartRate != nil
            case .hrv: night.avgHRV != nil
            case .respiratoryRate: night.avgRespiratoryRate != nil
            case .spo2: night.avgSpO2 != nil
            case .wristTemperature: night.wristTempDeltaC != nil
            case .breathing: night.breathingDisturbances != nil || night.breathingDisturbancesClassification != nil
            }
        }
    }

    /// One metric's coverage over the window.
    struct Coverage: Identifiable, Sendable {
        let metric: Metric
        var id: Metric.ID { metric.id }
        /// Nights in the window with a usable reading.
        let presentNightCount: Int
        /// Nights actually stored in the window -- not always equal to
        /// `expectedNightCount` when history is shorter than the window
        /// itself (a new install, or a gap).
        let totalNightCount: Int
        /// Calendar days the window spans, regardless of how many of them
        /// have a stored night at all -- what `.sleep`'s own coverage is
        /// measured against, so a week with three genuinely untracked
        /// nights reads as 4/7, not a misleadingly perfect 4/4.
        let expectedNightCount: Int

        private var denominator: Int { max(expectedNightCount, 1) }

        /// 0...1. Always against `expectedNightCount`, even for a
        /// secondary metric -- a night that's missing entirely is exactly
        /// as much a coverage gap for HRV as a night that exists but has
        /// no HRV reading on it. Clamped so two rows on one calendar day
        /// can never read as more than complete.
        var fraction: Double {
            min(1, Double(presentNightCount) / Double(denominator))
        }

        var percent: Int { Int((fraction * 100).rounded()) }

        enum Confidence: String, Sendable {
            case strong, limited, insufficient

            var label: String {
                switch self {
                case .strong: "Reliable"
                case .limited: "Limited"
                case .insufficient: "Insufficient"
                }
            }
        }

        /// Thresholds match the same rough shape `SleepHealth.Confidence`
        /// already uses elsewhere for "is there enough here to trust this."
        var confidence: Confidence {
            switch fraction {
            case 0.8...: .strong
            case 0.4..<0.8: .limited
            default: .insufficient
            }
        }
    }

    let windowDays: Int
    let coverage: [Coverage]

    /// - Parameters:
    ///   - nights: full stored history, any order.
    ///   - windowDays: trailing window size. 30 by default -- long enough
    ///     to smooth over a night or two of a watch left uncharged, short
    ///     enough that a stretch of genuinely bad coverage still shows up
    ///     as bad rather than being diluted by months of good data.
    ///   - now: injectable for tests.
    static func compute(nights: [SleepNightFeatures], windowDays: Int = 30, now: Date = .now, calendar: Calendar = .current) -> DataQuality {
        // `night.date` is always a startOfDay midnight value (see
        // SleepNightFeatures.date), so the cutoff needs to be midnight too --
        // otherwise a night from exactly `windowDays` ago (midnight) reads as
        // older than a same-day-clock-time cutoff and drops out of the
        // window whenever `now` isn't itself midnight, i.e. always.
        //
        // `windowDays - 1` because the window is inclusive at both ends and
        // today is one of its days: a 30-day window is today plus the 29
        // days before it. Going back a full `windowDays` spans 31 calendar
        // days against an `expectedNightCount` of 30, and a fully tracked
        // month then reads as 103% coverage.
        let rawCutoff = calendar.date(byAdding: .day, value: -(windowDays - 1), to: now) ?? now
        let cutoff = calendar.startOfDay(for: rawCutoff)
        let windowed = nights.filter { $0.date >= cutoff && $0.date <= now }

        let coverage = Metric.allCases.map { metric -> Coverage in
            let present = windowed.filter(metric.isPresent).count
            return Coverage(
                metric: metric,
                presentNightCount: present,
                totalNightCount: windowed.count,
                expectedNightCount: windowDays
            )
        }

        return DataQuality(windowDays: windowDays, coverage: coverage)
    }
}

// MARK: - When it stopped, not only how much there is

extension DataQuality {

    /// The timeline half of data quality: when a metric was last seen, rather
    /// than what fraction of the window it covered.
    ///
    /// `Coverage` above answers "how much HRV is there" and answers it well.
    /// It cannot answer the question somebody actually has when a number goes
    /// quiet, which is *when did this stop*. Sixty-two percent coverage reads
    /// the same whether the readings are scattered through the month or
    /// stopped dead eleven nights ago, and those are completely different
    /// situations: one is a watch charged irregularly, the other is a sensor,
    /// a permission or a pairing that broke on a particular day.
    ///
    /// Read-only and diagnostic, exactly as `Coverage` is. Nothing here feeds
    /// back into a score.
    struct Lapse: Identifiable, Sendable {
        let metric: Metric
        var id: Metric.ID { metric.id }

        /// The most recent stored night that carried a reading, or `nil` when
        /// no night in the history ever did.
        let lastSeen: Date?

        /// Stored nights after `lastSeen`, every one of which lacked the
        /// metric by construction. Zero means the most recent night has it.
        let nightsSince: Int

        /// Nights examined. A lapse of two out of two is not the same claim
        /// as a lapse of two out of ninety, and the wording below leans on
        /// knowing which.
        let nightsConsidered: Int

        enum Status: Sendable, Equatable {
            /// Arriving: the most recent stored night carried a reading.
            case current
            /// Was arriving, then stopped, for this many stored nights.
            case lapsed(nights: Int)
            /// No night on record has ever carried one.
            ///
            /// Deliberately distinct from `lapsed`. A metric that never
            /// appeared is usually a device that does not measure it or a
            /// permission never granted -- not something that broke -- and
            /// telling somebody their SpO2 "stopped" when their watch never
            /// reported it is a false claim about their hardware.
            case neverSeen
        }

        var status: Status {
            guard lastSeen != nil else { return .neverSeen }
            return nightsSince == 0 ? .current : .lapsed(nights: nightsSince)
        }

        /// A line for the diagnostic screen. States what is known and stops.
        var summary: String {
            switch status {
            case .current:
                "Arriving"
            case .lapsed(let nights):
                nights == 1
                    ? "Not in the most recent night"
                    : "Not in the last \(nights) nights"
            case .neverSeen:
                nightsConsidered == 0
                    ? "No nights recorded yet"
                    : "Not seen on this device"
            }
        }
    }

    /// One `Lapse` per metric, over the same history `compute` reads.
    ///
    /// `.sleep` is a special case by construction and not a bug: a night's
    /// presence in the array *is* its sleep measurement, so that row can only
    /// ever read `current` or, on an empty history, `neverSeen`. It is kept
    /// rather than dropped so this list lines up row-for-row with `coverage`.
    ///
    /// - Parameter nights: full stored history, any order. Sorted here rather
    ///   than trusted, the same as `compute` does.
    static func lapses(nights: [SleepNightFeatures]) -> [Lapse] {
        let ordered = nights.sorted { $0.date < $1.date }
        return Metric.allCases.map { metric in
            // Walk back from the most recent night. The first night carrying
            // the metric ends the walk, and everything stepped over is the
            // lapse -- which is why this counts stored nights rather than
            // calendar days: a night nobody recorded is a gap in sleep
            // coverage, and reporting it as a gap in HRV would blame the
            // wrong sensor.
            var nightsSince = 0
            var lastSeen: Date?
            for night in ordered.reversed() {
                if metric.isPresent(in: night) {
                    lastSeen = night.date
                    break
                }
                nightsSince += 1
            }
            return Lapse(
                metric: metric,
                lastSeen: lastSeen,
                nightsSince: lastSeen == nil ? 0 : nightsSince,
                nightsConsidered: ordered.count
            )
        }
    }
}
