import Foundation

/// Structured, pre-computed features for a single night of sleep.
///
/// This is the boundary between raw HealthKit samples and everything else in the
/// app. Raw `HKSample` arrays never leave `Services/` — views, the insight
/// engines, the widget, and (eventually) the local LLM all consume this struct.
///
/// Two reasons that matters:
/// 1. **Token budget.** The LLM layer gets a compact JSON summary, not a dump of
///    several hundred samples.
/// 2. **Testability.** Every downstream layer can be exercised with mock values
///    (see `MockData.swift`) with no HealthKit, no device, and no entitlements.
///
/// `Sendable` because the extraction pipeline runs off the main actor and hands
/// finished values back to `@MainActor` state.
struct SleepNightFeatures: Codable, Identifiable, Hashable, Sendable {

    /// Calendar day the night is filed under — the date you *woke up*.
    ///
    /// A night that starts 23:40 Tuesday and ends 07:10 Wednesday is "Wednesday".
    /// This matches how Apple Health and every consumer sleep app label nights,
    /// and it keeps one-row-per-day invariants simple in SwiftData.
    let date: Date

    var id: Date { date }

    // MARK: - Session bounds

    /// When the sleep session began (first in-bed or asleep sample).
    let bedtime: Date
    /// When the sleep session ended (last sample's end).
    let wakeTime: Date

    // MARK: - Duration & structure (minutes)

    let timeInBedMinutes: Double
    let timeAsleepMinutes: Double
    /// `timeAsleep / timeInBed * 100`. Clamped to 0...100.
    let sleepEfficiencyPercent: Double

    let coreMinutes: Double
    let deepMinutes: Double
    let remMinutes: Double
    /// Sleep recorded with no stage breakdown.
    ///
    /// Sources that aren't an Apple Watch with sleep staging (iPhone-only sleep
    /// schedule, most third-party trackers, older watchOS) write **only**
    /// `asleepUnspecified`. Dropping it is the single most common way to end up
    /// showing a real user "0h 0m" for a night they actually slept — so it is a
    /// first-class field, and it counts toward `timeAsleepMinutes`.
    let unspecifiedAsleepMinutes: Double
    let awakeMinutes: Double

    /// Awakenings *after* sleep onset. Restlessness before you fall asleep is
    /// not fragmentation, so pre-onset awake samples are excluded.
    let wakeCount: Int

    /// Minutes from first in-bed to first asleep sample.
    ///
    /// `nil` when the source writes no `inBed` samples at all — Apple Watch
    /// alone does not, so this is only populated when iPhone sleep schedule or a
    /// third-party app contributed in-bed data.
    let sleepLatencyMinutes: Double?

    // MARK: - Physiology (averaged across the session)

    let avgHeartRate: Double?
    /// Resting-ish low: the minimum heart rate observed during the session, a
    /// steadier night-to-night signal than the mean.
    let minHeartRate: Double?
    /// SDNN, milliseconds.
    let avgHRV: Double?
    /// Breaths per minute.
    let avgRespiratoryRate: Double?
    /// Blood oxygen, **percent** (0–100), already converted from HealthKit's
    /// 0–1 fraction representation.
    let avgSpO2: Double?
    /// Wrist temperature deviation from the user's own baseline, in °C.
    /// Positive = warmer than usual. Requires ~7 nights of history to populate.
    let wristTempDeltaC: Double?

    // MARK: - Context (needs history, not just this night)

    /// Mean overnight HRV across the previous 7 nights, excluding this one.
    let hrv7DayAvg: Double?
    /// Cumulative shortfall against the user's sleep goal over 14 days, in
    /// minutes. Positive = under-slept. Never negative — banking extra sleep
    /// does not create credit.
    let sleepDebtMinutes14Day: Double?
    /// Hours between the end of the last workout and `bedtime`.
    /// `nil` if no workout that day.
    let lastWorkoutHoursBeforeBed: Double?
    /// Total Apple Exercise minutes on the calendar day before this night.
    let exerciseMinutesPreviousDay: Double?

    // MARK: - Provenance

    /// Which HealthKit source the stage data came from, e.g. "Ishfaq's Apple Watch".
    /// Shown in Settings so the user can see what's feeding the app.
    let sourceName: String?

    /// True when this record is synthetic sample data rather than real HealthKit
    /// output. Views badge these so a Simulator screenshot is never mistaken for
    /// a real night.
    var isMock: Bool = false

    /// The night's shape: every stage run in chronological order.
    ///
    /// Declared last with a default so it stays optional at every existing call
    /// site. Empty is a legitimate value — sources without staging produce no
    /// segments, and the hypnogram hides itself rather than drawing a flat line.
    var stageSegments: [StageSegment] = []
}

// MARK: - Derived values

extension SleepNightFeatures {

    /// Total staged sleep, i.e. everything except awake time.
    var stagedAsleepMinutes: Double {
        coreMinutes + deepMinutes + remMinutes + unspecifiedAsleepMinutes
    }

    /// True when the source gave us a real stage breakdown. When false, the UI
    /// hides the stage chart instead of drawing four empty bars.
    var hasStageBreakdown: Bool {
        (coreMinutes + deepMinutes + remMinutes) > 0
    }

    var deepPercentOfAsleep: Double? {
        guard hasStageBreakdown, timeAsleepMinutes > 0 else { return nil }
        return deepMinutes / timeAsleepMinutes * 100
    }

    var remPercentOfAsleep: Double? {
        guard hasStageBreakdown, timeAsleepMinutes > 0 else { return nil }
        return remMinutes / timeAsleepMinutes * 100
    }

    /// "7h 24m"
    var formattedTimeAsleep: String {
        Self.formatMinutes(timeAsleepMinutes)
    }

    static func formatMinutes(_ minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        return "\(total / 60)h \(total % 60)m"
    }
}

// MARK: - LLM prompt payload

extension SleepNightFeatures {

    /// Compact JSON summary intended as prompt input for `LocalLLMInsightEngine`.
    ///
    /// Built with `JSONEncoder` rather than string interpolation on purpose: the
    /// moment a free-text field lands in here (a source name, a user note), hand
    /// -rolled JSON becomes an escaping bug and a prompt-injection surface.
    ///
    /// Keys are snake_case and deliberately terse — this is model input, not an
    /// API contract.
    var summaryForLLM: String {
        let payload = LLMPayload(
            date: ISO8601DateFormatter.dayOnly.string(from: date),
            sleepEfficiencyPct: sleepEfficiencyPercent.rounded(to: 1),
            timeAsleepMin: Int(timeAsleepMinutes.rounded()),
            timeInBedMin: Int(timeInBedMinutes.rounded()),
            deepMin: hasStageBreakdown ? Int(deepMinutes.rounded()) : nil,
            remMin: hasStageBreakdown ? Int(remMinutes.rounded()) : nil,
            coreMin: hasStageBreakdown ? Int(coreMinutes.rounded()) : nil,
            wakeCount: wakeCount,
            sleepLatencyMin: sleepLatencyMinutes?.rounded(to: 0),
            avgHrvMs: avgHRV?.rounded(to: 0),
            hrv7dayAvgMs: hrv7DayAvg?.rounded(to: 0),
            minHeartRate: minHeartRate?.rounded(to: 0),
            avgRespiratoryRate: avgRespiratoryRate?.rounded(to: 1),
            avgSpo2Pct: avgSpO2?.rounded(to: 1),
            wristTempDeltaC: wristTempDeltaC?.rounded(to: 2),
            sleepDebtMin14day: sleepDebtMinutes14Day?.rounded(to: 0),
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed?.rounded(to: 1),
            exerciseMinPreviousDay: exerciseMinutesPreviousDay?.rounded(to: 0)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Flat DTO so `JSONEncoder` emits exactly the keys the prompt expects.
    /// `nil` fields are omitted entirely rather than encoded as `null`, which
    /// keeps the prompt shorter and avoids the model reasoning about absent data
    /// as if it were a measured zero.
    private struct LLMPayload: Encodable {
        let date: String
        let sleepEfficiencyPct: Double
        let timeAsleepMin: Int
        let timeInBedMin: Int
        let deepMin: Int?
        let remMin: Int?
        let coreMin: Int?
        let wakeCount: Int
        let sleepLatencyMin: Double?
        let avgHrvMs: Double?
        let hrv7dayAvgMs: Double?
        let minHeartRate: Double?
        let avgRespiratoryRate: Double?
        let avgSpo2Pct: Double?
        let wristTempDeltaC: Double?
        let sleepDebtMin14day: Double?
        let lastWorkoutHoursBeforeBed: Double?
        let exerciseMinPreviousDay: Double?

        enum CodingKeys: String, CodingKey {
            case date
            case sleepEfficiencyPct = "sleep_efficiency_pct"
            case timeAsleepMin = "time_asleep_min"
            case timeInBedMin = "time_in_bed_min"
            case deepMin = "deep_min"
            case remMin = "rem_min"
            case coreMin = "core_min"
            case wakeCount = "wake_count"
            case sleepLatencyMin = "sleep_latency_min"
            case avgHrvMs = "avg_hrv_ms"
            case hrv7dayAvgMs = "hrv_7day_avg_ms"
            case minHeartRate = "min_heart_rate"
            case avgRespiratoryRate = "avg_respiratory_rate"
            case avgSpo2Pct = "avg_spo2_pct"
            case wristTempDeltaC = "wrist_temp_delta_c"
            case sleepDebtMin14day = "sleep_debt_min_14day"
            case lastWorkoutHoursBeforeBed = "last_workout_hours_before_bed"
            case exerciseMinPreviousDay = "exercise_min_previous_day"
        }
    }
}

// MARK: - Small helpers

extension Double {
    /// Rounds to `places` decimal places. Used to keep the LLM payload tidy —
    /// `7.000000000001` costs tokens and buys nothing.
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

extension ISO8601DateFormatter {
    /// Date-only ISO formatter. The LLM never needs the wall-clock time of the
    /// record, and including it invites the model to reason about timezones.
    static let dayOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
