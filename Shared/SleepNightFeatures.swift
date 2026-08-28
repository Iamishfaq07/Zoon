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
    /// False when the source wrote real HealthKit `inBed` samples, so
    /// `timeInBedMinutes` is measured. True when it didn't -- Apple Watch
    /// alone never does -- and `timeInBedMinutes` is standing in for it with
    /// the asleep/awake session span instead, which omits any time spent
    /// lying awake before falling asleep or after the final waking, and so
    /// tends to overstate `sleepEfficiencyPercent` slightly. Declared with a
    /// default so it stays optional at every existing call site.
    var timeInBedIsEstimated: Bool = false
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
    /// The lowest heart-rate sample observed during the sleep session -- a
    /// single noisy reading, not a resting heart rate. Kept for the "sleeping
    /// low" display and for existing history; anything that means *resting
    /// heart rate* should read `restingHeartRate` instead. See that
    /// property's doc comment for why these are not interchangeable.
    let minHeartRate: Double?
    /// True resting heart rate, from HealthKit's daily `.restingHeartRate`
    /// sample -- the value Apple itself computes from a rolling window of
    /// low-activity heart-rate readings, distinct from `minHeartRate`.
    ///
    /// `minHeartRate` used to be displayed and scored as "Resting HR"
    /// throughout the app; it is not one. It is the single lowest heart-rate
    /// sample observed during a sleep session, which can be noisy (one good
    /// low reading during a brief deep-sleep dip reads no differently than a
    /// stable low night). This field is Apple's own daily RHR figure, sourced
    /// from a type this app didn't previously request read access to at all.
    ///
    /// `nil` when no daily resting-heart-rate sample overlaps this night's
    /// date -- e.g. the Watch wasn't worn during the day, or on a night
    /// imported before this field existed. Declared with a default so it
    /// stays optional at every existing call site.
    var restingHeartRate: Double? = nil
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

    /// Apple's overnight breathing-disturbance measure, as a percentage of the
    /// night. This is the signal behind Apple Watch's sleep apnea notifications.
    ///
    /// Declared with a default so it stays optional at existing call sites.
    /// Requires an Apple Watch Series 9 / Ultra 2 or later with the feature
    /// enabled; `nil` on everything else.
    var breathingDisturbances: Double? = nil

    /// Apple's own elevated/not-elevated classification of the value above,
    /// from `HKAppleSleepingBreathingDisturbancesClassification(for:)` (iOS
    /// 18+) -- see `BreathingDisturbanceClassification`'s doc comment.
    /// Declared with a default for the same reason `breathingDisturbances`
    /// is: `nil` on any night extracted before this existed, or wherever
    /// HealthKit didn't provide a classification for the measured value.
    var breathingDisturbancesClassification: BreathingDisturbanceClassification? = nil

    // MARK: - Context (needs history, not just this night)

    /// Mean overnight HRV across the previous 7 nights, excluding this one.
    let hrv7DayAvg: Double?
    /// Cumulative shortfall against the user's sleep goal over 14 days, in
    /// minutes. Positive = under-slept. Never negative — banking extra sleep
    /// does not create credit.
    let sleepDebtMinutes: Double?
    /// Hours between the end of the last workout and `bedtime`.
    /// `nil` if no workout that day.
    let lastWorkoutHoursBeforeBed: Double?
    /// Total Apple Exercise minutes on the calendar day before this night.
    let exerciseMinutesPreviousDay: Double?

    /// Minutes asleep across secondary episodes tied to this night -- naps
    /// and split-sleep blocks that `timeAsleepMinutes` (the main sleep
    /// session alone) doesn't include. See
    /// `SleepHistoryStore.secondaryEpisodeAsleepMinutes`. Declared with a
    /// default so it stays optional at every existing call site; 0 for mock
    /// data and any night built without a secondary-episode lookup, which
    /// just means that night's debt/need math sees main sleep only, same as
    /// before this field existed.
    var secondaryAsleepMinutes: Double = 0

    /// The sleep-need baseline that was authoritative when this night was
    /// processed, frozen forever after -- see
    /// `SleepNightRecord.sleepNeedBaselineMinutesAtProcessing`'s doc comment
    /// for why. `nil` for nights stored before this field existed; consumers
    /// fall back to the current Settings goal. Declared with a default so it
    /// stays optional at every existing call site.
    var sleepNeedBaselineMinutes: Double? = nil

    /// Alcoholic beverages logged the day of bedtime, up to bedtime -- and
    /// caffeine logged after 4pm that same day. Measured directly from
    /// HealthKit (`.numberOfAlcoholicBeverages`, `.dietaryCaffeine`)
    /// regardless of whether the Lifestyle Insights permission group was
    /// ever granted -- an unauthorized read type simply returns no data, so
    /// these stay `nil` for anyone who hasn't logged either in Health, same
    /// as every other optional HealthKit-derived field here. Declared with a
    /// default so both stay optional at every existing call site.
    var alcoholicBeverages: Double? = nil
    var lateCaffeineMg: Double? = nil

    // MARK: - Provenance

    /// Which HealthKit source the stage data came from, e.g. "Ishfaq's Apple Watch".
    /// Shown in Settings so the user can see what's feeding the app.
    let sourceName: String?

    /// `sourceRevision.source.bundleIdentifier` for the same source --
    /// stable across a device rename or a display-language change, unlike
    /// `sourceName`. See `SleepSessionBuilder.SleepSession.sourceBundleIdentifier`'s
    /// doc comment; this is the same value carried one layer further so
    /// Settings' "preferred source" picker can offer a stable identity to
    /// match against instead of the display name alone.
    let sourceBundleIdentifier: String?

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

    /// Timezone the HealthKit samples were recorded in, not the device's
    /// current one -- see `SleepSession.timeZoneIdentifier`. Anything that
    /// extracts a wall-clock hour or a weekday from `bedtime`/`wakeTime` for
    /// a *historical* night (chronotype, regularity's midpoints) must use
    /// this, not `Calendar.current`, or a traveler's past nights silently
    /// reclassify themselves every time the device's timezone changes.
    /// Declared with a default so it stays optional at every existing call
    /// site; defaults to the device's timezone at construction time, which is
    /// only wrong for mock/test data that doesn't care.
    var timeZoneIdentifier: String = TimeZone.current.identifier

    // MARK: - Init

    /// Restates the memberwise initializer the compiler would otherwise
    /// synthesize. Required because providing a custom `init(from:)` below
    /// (for backup-compatibility -- see its doc comment) suppresses that
    /// synthesis entirely, and every construction call site across the app
    /// depends on it, including omitting the fields that default here.
    init(
        date: Date,
        bedtime: Date,
        wakeTime: Date,
        timeInBedMinutes: Double,
        timeInBedIsEstimated: Bool = false,
        timeAsleepMinutes: Double,
        sleepEfficiencyPercent: Double,
        coreMinutes: Double,
        deepMinutes: Double,
        remMinutes: Double,
        unspecifiedAsleepMinutes: Double,
        awakeMinutes: Double,
        wakeCount: Int,
        sleepLatencyMinutes: Double?,
        avgHeartRate: Double?,
        minHeartRate: Double?,
        restingHeartRate: Double? = nil,
        avgHRV: Double?,
        avgRespiratoryRate: Double?,
        avgSpO2: Double?,
        wristTempDeltaC: Double?,
        breathingDisturbances: Double? = nil,
        breathingDisturbancesClassification: BreathingDisturbanceClassification? = nil,
        hrv7DayAvg: Double?,
        sleepDebtMinutes: Double?,
        lastWorkoutHoursBeforeBed: Double?,
        exerciseMinutesPreviousDay: Double?,
        secondaryAsleepMinutes: Double = 0,
        sleepNeedBaselineMinutes: Double? = nil,
        alcoholicBeverages: Double? = nil,
        lateCaffeineMg: Double? = nil,
        sourceName: String?,
        sourceBundleIdentifier: String? = nil,
        isMock: Bool = false,
        stageSegments: [StageSegment] = [],
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.date = date
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.timeInBedMinutes = timeInBedMinutes
        self.timeInBedIsEstimated = timeInBedIsEstimated
        self.timeAsleepMinutes = timeAsleepMinutes
        self.sleepEfficiencyPercent = sleepEfficiencyPercent
        self.coreMinutes = coreMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.unspecifiedAsleepMinutes = unspecifiedAsleepMinutes
        self.awakeMinutes = awakeMinutes
        self.wakeCount = wakeCount
        self.sleepLatencyMinutes = sleepLatencyMinutes
        self.avgHeartRate = avgHeartRate
        self.minHeartRate = minHeartRate
        self.restingHeartRate = restingHeartRate
        self.avgHRV = avgHRV
        self.avgRespiratoryRate = avgRespiratoryRate
        self.avgSpO2 = avgSpO2
        self.wristTempDeltaC = wristTempDeltaC
        self.breathingDisturbances = breathingDisturbances
        self.breathingDisturbancesClassification = breathingDisturbancesClassification
        self.hrv7DayAvg = hrv7DayAvg
        self.sleepDebtMinutes = sleepDebtMinutes
        self.lastWorkoutHoursBeforeBed = lastWorkoutHoursBeforeBed
        self.exerciseMinutesPreviousDay = exerciseMinutesPreviousDay
        self.secondaryAsleepMinutes = secondaryAsleepMinutes
        self.sleepNeedBaselineMinutes = sleepNeedBaselineMinutes
        self.alcoholicBeverages = alcoholicBeverages
        self.lateCaffeineMg = lateCaffeineMg
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.isMock = isMock
        self.stageSegments = stageSegments
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    // MARK: - Decoding

    /// Hand-written to close a real backward-compatibility gap: Swift's
    /// *synthesized* `Decodable` conformance does **not** fall back to a
    /// property's default value when its key is missing from the JSON --
    /// that only happens for `Optional`-typed properties. A non-Optional
    /// property declared `var x: T = default` (`timeInBedIsEstimated`,
    /// `secondaryAsleepMinutes`, `isMock`, `stageSegments`,
    /// `timeZoneIdentifier`) still throws `keyNotFound` on synthesized
    /// decode if the key is absent, which is exactly what an older export
    /// (format 1/2, or any format before the field existed) looks like.
    /// `DataExporter.decode` turns that throw into a generic "damaged file"
    /// error for the user -- a real backup, misreported as corrupt.
    ///
    /// Every field below is decoded with `decodeIfPresent(...) ?? default`,
    /// using literally the same default the property declares, so this
    /// matches what a reader would assume already happens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        bedtime = try c.decode(Date.self, forKey: .bedtime)
        wakeTime = try c.decode(Date.self, forKey: .wakeTime)
        timeInBedMinutes = try c.decode(Double.self, forKey: .timeInBedMinutes)
        timeInBedIsEstimated = try c.decodeIfPresent(Bool.self, forKey: .timeInBedIsEstimated) ?? false
        timeAsleepMinutes = try c.decode(Double.self, forKey: .timeAsleepMinutes)
        sleepEfficiencyPercent = try c.decode(Double.self, forKey: .sleepEfficiencyPercent)
        coreMinutes = try c.decode(Double.self, forKey: .coreMinutes)
        deepMinutes = try c.decode(Double.self, forKey: .deepMinutes)
        remMinutes = try c.decode(Double.self, forKey: .remMinutes)
        unspecifiedAsleepMinutes = try c.decode(Double.self, forKey: .unspecifiedAsleepMinutes)
        awakeMinutes = try c.decode(Double.self, forKey: .awakeMinutes)
        wakeCount = try c.decode(Int.self, forKey: .wakeCount)
        sleepLatencyMinutes = try c.decodeIfPresent(Double.self, forKey: .sleepLatencyMinutes)
        avgHeartRate = try c.decodeIfPresent(Double.self, forKey: .avgHeartRate)
        minHeartRate = try c.decodeIfPresent(Double.self, forKey: .minHeartRate)
        restingHeartRate = try c.decodeIfPresent(Double.self, forKey: .restingHeartRate)
        avgHRV = try c.decodeIfPresent(Double.self, forKey: .avgHRV)
        avgRespiratoryRate = try c.decodeIfPresent(Double.self, forKey: .avgRespiratoryRate)
        avgSpO2 = try c.decodeIfPresent(Double.self, forKey: .avgSpO2)
        wristTempDeltaC = try c.decodeIfPresent(Double.self, forKey: .wristTempDeltaC)
        breathingDisturbances = try c.decodeIfPresent(Double.self, forKey: .breathingDisturbances)
        breathingDisturbancesClassification = try c.decodeIfPresent(
            BreathingDisturbanceClassification.self, forKey: .breathingDisturbancesClassification
        )
        hrv7DayAvg = try c.decodeIfPresent(Double.self, forKey: .hrv7DayAvg)
        sleepDebtMinutes = try c.decodeIfPresent(Double.self, forKey: .sleepDebtMinutes)
        lastWorkoutHoursBeforeBed = try c.decodeIfPresent(Double.self, forKey: .lastWorkoutHoursBeforeBed)
        exerciseMinutesPreviousDay = try c.decodeIfPresent(Double.self, forKey: .exerciseMinutesPreviousDay)
        secondaryAsleepMinutes = try c.decodeIfPresent(Double.self, forKey: .secondaryAsleepMinutes) ?? 0
        sleepNeedBaselineMinutes = try c.decodeIfPresent(Double.self, forKey: .sleepNeedBaselineMinutes)
        alcoholicBeverages = try c.decodeIfPresent(Double.self, forKey: .alcoholicBeverages)
        lateCaffeineMg = try c.decodeIfPresent(Double.self, forKey: .lateCaffeineMg)
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName)
        sourceBundleIdentifier = try c.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
        isMock = try c.decodeIfPresent(Bool.self, forKey: .isMock) ?? false
        stageSegments = try c.decodeIfPresent([StageSegment].self, forKey: .stageSegments) ?? []
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
            ?? TimeZone.current.identifier
    }
}

// MARK: - Derived values

extension SleepNightFeatures {

    /// Total staged sleep, i.e. everything except awake time.
    var stagedAsleepMinutes: Double {
        coreMinutes + deepMinutes + remMinutes + unspecifiedAsleepMinutes
    }

    /// The day's true 24-hour asleep total: main sleep plus every secondary
    /// episode (naps, split-sleep blocks) tied to this night. Sleep debt and
    /// need are computed against this, not against `timeAsleepMinutes` alone
    /// -- a short main-sleep night followed by a compensating nap should not
    /// still read as a full night's shortfall.
    var total24hAsleepMinutes: Double {
        timeAsleepMinutes + secondaryAsleepMinutes
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

    /// `timeZoneIdentifier` resolved, falling back to the device's current
    /// timezone for an unresolvable or pre-migration identifier.
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// Stable local-date identity for this night, in the timezone it was
    /// actually recorded in -- not the device's current one. Same format as
    /// `SleepSession.nightKey` (the two describe the same night and are
    /// built from the same wake instant + recorded timezone, so they agree
    /// by construction), reproduced here as a computed value rather than a
    /// stored one since `date`/`timeZoneIdentifier` already carry everything
    /// needed to derive it.
    ///
    /// This is what contextual data -- Journal entries, naps, snore
    /// summaries -- should match a night against instead of comparing `Date`
    /// values under `Calendar.current`: two `Date`s that both look like
    /// "the start of some day" can disagree about *which* day the instant
    /// they wrap belongs to once the device's current timezone differs from
    /// the timezone the night itself happened in, e.g. right after a flight.
    var nightKey: String {
        NightKey.make(wakeInstant: date, in: timeZone)
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
            restingHeartRate: restingHeartRate?.rounded(to: 0),
            avgRespiratoryRate: avgRespiratoryRate?.rounded(to: 1),
            avgSpo2Pct: avgSpO2?.rounded(to: 1),
            wristTempDeltaC: wristTempDeltaC?.rounded(to: 2),
            sleepDebtMin14day: sleepDebtMinutes?.rounded(to: 0),
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
        let restingHeartRate: Double?
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
            case restingHeartRate = "resting_heart_rate"
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
