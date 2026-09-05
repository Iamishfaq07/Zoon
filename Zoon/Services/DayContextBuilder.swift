import Foundation

/// Assembles a `DayContext` from a night, stored history, and today's activity.
///
/// Pulled out of the coordinator because it's pure input→output with no
/// HealthKit and no SwiftData in sight — which means it can be exercised
/// entirely from mock data, and is the piece most worth reasoning about in
/// isolation when a number on screen looks wrong.
struct DayContextBuilder {

    /// Longer than the insight engine's 7-day window on purpose: recovery
    /// baselines that track a training block too closely stop noticing that
    /// you're buried in it.
    static let recoveryBaselineWindow = 30

    /// Window for the two "habitual timing" metrics -- `SleepRegularity` and
    /// `BodyClock` -- that, unlike their siblings below, don't do any
    /// internal windowing of their own: `CardiovascularAge` re-slices to its
    /// own `.suffix(30)` and `HealthRadar` to its own recent + baseline
    /// windows regardless of how much history is handed to them, but
    /// `SleepRegularity.compute`/`BodyClock.compute` use exactly the array
    /// they're given. Passing them the ever-growing full record meant a
    /// habitual bedtime or regularity index quietly became a lifetime
    /// average -- a genuine schedule change (new job, new baby, a permanent
    /// timezone move) got diluted more and more slowly the longer someone
    /// had used the app, instead of the "recent pattern" both are meant to
    /// describe. 60 nights is comfortably above each metric's own minimum
    /// (14 for BodyClock, 7 for SleepRegularity) while still adapting to a
    /// real change within a couple of months.
    static let habitWindow = 60

    struct Inputs {
        let night: SleepNightFeatures
        /// Produces the night's insight, given the flagship score's band.
        ///
        /// A closure rather than a finished `SleepInsight` because of an
        /// ordering problem that used to be resolved the wrong way. The
        /// insight's summary opens with a word for the whole night --
        /// "Strong night", "Rough night" -- and that word must come from
        /// Sleep Intelligence, which is computed in here. The insight was
        /// generated before this builder ran, so the engine had nothing to
        /// grade the night with but `SleepScore`, and the most-read sentence
        /// in the app could call a night "Mixed" while the hero orb two lines
        /// above it graded the same night Good.
        ///
        /// Passing the engine's work in as a closure keeps Sleep Intelligence
        /// computed exactly once, here, and hands it to the sentence that
        /// quotes it. The alternative -- computing the score a second time at
        /// the call site -- is two computations that can silently disagree.
        let insight: (SleepIntelligenceScore.Band) -> SleepInsight
        /// Stored nights, oldest first, **excluding** tonight.
        let history: [SleepNightFeatures]
        let goalMinutes: Double
        let yesterdayStrain: StrainScore
        let todayStrain: StrainScore
        /// Hourly heart rate for today, for the body battery curve.
        let hourlyHeartRate: [(date: Date, bpm: Double)]
        /// Age-derived or measured. Used for heart-rate reserve.
        let maxHeartRate: Double
        let napMinutes: Double
        let bedtimeConsistencyMinutes: Double?
        /// For cardiovascular age. Nil disables that card rather than guessing.
        let age: Int?
        /// `Calendar.component(.weekday:)` values counted as obligation days,
        /// for `SleepRegularity`'s work/free split -- see
        /// `UserPreferences.obligationWeekdays`.
        var obligationWeekdays: Set<Int> = SleepRegularity.defaultObligationWeekdays
    }

    func build(_ inputs: Inputs) -> DayContext {
        let night = inputs.night
        let history = inputs.history

        // --- Baselines ----------------------------------------------------
        let window = Array(history.suffix(Self.recoveryBaselineWindow))
        // Per-metric sample gating lives in the factory -- see
        // RecoveryBaseline.minimumSamplesPerMetric for why a shared
        // window-wide night count isn't good enough.
        let recoveryBaseline = RecoveryBaseline.from(nights: window)

        // --- Sleep need ---------------------------------------------------
        // The baseline SleepNeed builds on top of is the learned figure once
        // there's enough history for one, not always the raw Settings goal --
        // see LearnedSleepNeed's own doc comment for why a straight average
        // of past nights isn't used instead.
        let learnedNeed = LearnedSleepNeed.compute(goalMinutes: inputs.goalMinutes, history: history)
        let sleepNeed = SleepNeed.compute(
            goalMinutes: learnedNeed.minutes,
            outstandingDebtMinutes: night.sleepDebtMinutes ?? 0,
            yesterdayStrain: inputs.yesterdayStrain.value,
            napMinutes: inputs.napMinutes,
            achievedMinutes: night.timeAsleepMinutes
        )

        // --- Recovery -----------------------------------------------------
        let recovery = RecoveryScore.compute(
            features: night,
            baseline: recoveryBaseline,
            sleepPerformance: sleepNeed.performancePercent
        )

        // --- Body battery -------------------------------------------------
        // Resting HR falls back through the night's own true RHR, then its
        // sleep-window low, then a plausible default — a nil here would zero
        // the drain model rather than degrade it. Body Battery is a wellness
        // curve, not a scored component, so this looser fallback chain (unlike
        // RecoveryBaseline above) is an acceptable approximation.
        let restingHR = recoveryBaseline.restingHeartRate ?? night.restingHeartRate ?? night.minHeartRate ?? 60
        let bodyBattery = BodyBattery.build(
            startLevel: BodyBattery.overnightCharge(
                recoveryPercent: recovery.percent,
                sleepPerformance: sleepNeed.performancePercent
            ),
            wakeTime: night.wakeTime,
            hourlyHeartRate: inputs.hourlyHeartRate,
            restingHeartRate: restingHR,
            maxHeartRate: inputs.maxHeartRate
        )

        // --- Vitals -------------------------------------------------------
        let vitals = VitalsStatus.evaluate(
            features: night,
            history: window.map {
                VitalsSample(
                    date: $0.date,
                    restingHeartRate: $0.restingHeartRate,
                    hrv: $0.avgHRV,
                    respiratoryRate: $0.avgRespiratoryRate,
                    oxygenSaturation: $0.avgSpO2,
                    wristTemperatureDelta: $0.wristTempDeltaC,
                    sleepMinutes: $0.timeAsleepMinutes,
                    breathingDisturbances: $0.breathingDisturbances
                )
            }
        )

        // --- HRV status ---------------------------------------------------
        let hrvStatus = HRVStatus.evaluate(
            recentHRV: Array(history.suffix(7)).compactMap(\.avgHRV),
            longTermHRV: history.compactMap(\.avgHRV)
        )

        // --- Chronotype ---------------------------------------------------
        let allNights = history + [night]
        let chronotype = Chronotype.infer(
            bedtimeHours: allNights.map { Self.shiftedBedtimeHour($0.bedtime, timeZone: $0.timeZone) },
            durations: allNights.map(\.timeAsleepMinutes),
            consistencyMinutes: inputs.bedtimeConsistencyMinutes
        )

        // Regularity, radar and CV age all read a span including tonight
        // rather than tonight alone. Radar and CV age get the unbounded
        // record because each does its own internal windowing regardless of
        // input size; regularity and body clock get a bounded recent window
        // instead, since neither windows internally — see `habitWindow`'s
        // doc comment for why passing them the full record was a bug.
        let fullHistory = history + [night]
        let habitWindow = Array(fullHistory.suffix(Self.habitWindow))

        let regularity = SleepRegularity.compute(nights: habitWindow, obligationWeekdays: inputs.obligationWeekdays)
        let bodyClock = BodyClock.compute(nights: habitWindow)

        let sleepIntelligence = SleepIntelligenceScore.compute(.init(
            night: night,
            history: history,
            sleepNeedMinutes: sleepNeed.totalNeedMinutes,
            // `SleepRegularity.compute` returns a hardcoded index of 0 -- not
            // nil -- below its own `minimumNights` (7), since SRI needs a full
            // week of consecutive-night comparisons to mean anything. Gating on
            // `hasEnoughData` here (rather than a separate, looser threshold)
            // is what keeps that 0 from ever being read as "no regularity"
            // instead of "not enough history yet" -- a new user with 3-6
            // nights was previously scored as having zero regularity, the
            // worst possible value, purely for being new.
            regularityIndex: regularity.hasEnoughData ? regularity.index : nil,
            habitualMidpointHours: bodyClock?.isEstimate == false ? bodyClock?.midpoint : nil
        ))

        return DayContext(
            night: night,
            insight: inputs.insight(sleepIntelligence.band),
            recovery: recovery,
            sleepNeed: sleepNeed,
            learnedSleepNeed: learnedNeed,
            sleepScore: SleepScore.compute(for: night, goalMinutes: inputs.goalMinutes),
            sleepIntelligence: sleepIntelligence,
            strain: inputs.todayStrain,
            bodyBattery: bodyBattery,
            vitals: vitals,
            hrvStatus: hrvStatus,
            chronotype: chronotype,
            regularity: regularity,
            healthRadar: HealthRadar.detect(nights: fullHistory),
            cardiovascularAge: CardiovascularAge.compute(
                nights: fullHistory, chronologicalAge: inputs.age
            ),
            bodyClock: bodyClock,
            hourlyHeartRate: inputs.hourlyHeartRate
        )
    }

    /// Bedtime as hours from midnight, evening negative (23:30 → −0.5).
    ///
    /// Same convention the consistency chart uses. Without the shift, a steady
    /// 23:50 sleeper and a steady 00:10 sleeper look 23 hours apart.
    ///
    /// - Parameter timeZone: the night's own timezone, not the device's
    ///   current one -- a historical bedtime's wall-clock hour doesn't change
    ///   because the user has since traveled. Defaults to `.current` only for
    ///   call sites with no per-night timezone available (mock data).
    static func shiftedBedtimeHour(_ date: Date, timeZone: TimeZone = .current) -> Double {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return hour >= 18 ? hour - 24 : hour
    }

    /// Age-predicted maximum heart rate (Tanaka), used when nothing better is
    /// available. Closer to observed values across adult ages than the older
    /// 220−age rule, which systematically underestimates for over-40s.
    static func estimatedMaxHeartRate(age: Int?) -> Double {
        guard let age, age > 0, age < 120 else { return 190 }
        return 208 - 0.7 * Double(age)
    }
}
