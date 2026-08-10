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

    struct Inputs {
        let night: SleepNightFeatures
        let insight: SleepInsight
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
    }

    func build(_ inputs: Inputs) -> DayContext {
        let night = inputs.night
        let history = inputs.history

        // --- Baselines ----------------------------------------------------
        let window = Array(history.suffix(Self.recoveryBaselineWindow))
        let recoveryBaseline = RecoveryBaseline(
            hrv: mean(window.compactMap(\.avgHRV)),
            restingHeartRate: mean(window.compactMap(\.minHeartRate)),
            respiratoryRate: mean(window.compactMap(\.avgRespiratoryRate)),
            wristTemperature: mean(window.compactMap(\.wristTempDeltaC)),
            nightCount: window.count
        )

        // --- Sleep need ---------------------------------------------------
        let sleepNeed = SleepNeed.compute(
            goalMinutes: inputs.goalMinutes,
            outstandingDebtMinutes: night.sleepDebtMinutes14Day ?? 0,
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
        // Resting HR falls back to the night's own low, then to a plausible
        // default — a nil here would zero the drain model rather than degrade it.
        let restingHR = recoveryBaseline.restingHeartRate ?? night.minHeartRate ?? 60
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
                    restingHeartRate: $0.minHeartRate,
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
            bedtimeHours: allNights.map { Self.shiftedBedtimeHour($0.bedtime) },
            durations: allNights.map(\.timeAsleepMinutes),
            consistencyMinutes: inputs.bedtimeConsistencyMinutes
        )

        // Regularity, radar and CV age all read the full record including
        // tonight — they describe a span, not a single night.
        let fullHistory = history + [night]

        return DayContext(
            night: night,
            insight: inputs.insight,
            recovery: recovery,
            sleepNeed: sleepNeed,
            sleepScore: SleepScore.compute(for: night, goalMinutes: inputs.goalMinutes),
            strain: inputs.todayStrain,
            bodyBattery: bodyBattery,
            vitals: vitals,
            hrvStatus: hrvStatus,
            chronotype: chronotype,
            regularity: SleepRegularity.compute(nights: fullHistory),
            healthRadar: HealthRadar.detect(nights: fullHistory),
            cardiovascularAge: CardiovascularAge.compute(
                nights: fullHistory, chronologicalAge: inputs.age
            ),
            bodyClock: BodyClock.compute(nights: fullHistory)
        )
    }

    /// Bedtime as hours from midnight, evening negative (23:30 → −0.5).
    ///
    /// Same convention the consistency chart uses. Without the shift, a steady
    /// 23:50 sleeper and a steady 00:10 sleeper look 23 hours apart.
    static func shiftedBedtimeHour(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
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

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
