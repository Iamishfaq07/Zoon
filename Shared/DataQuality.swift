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
        /// no HRV reading on it.
        var fraction: Double {
            Double(presentNightCount) / Double(denominator)
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
        let rawCutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
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
