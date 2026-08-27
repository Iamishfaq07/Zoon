import Foundation

/// Synthetic sleep data.
///
/// This exists because **HealthKit sleep data does not work in the iOS
/// Simulator.** There is no way to get a realistic night out of a simulated
/// device, so without mocks every SwiftUI preview and every Simulator run would
/// show an empty state and the UI would be undevelopable.
///
/// Everything here sets `isMock: true`, and the UI badges mock nights, so a
/// screenshot from the Simulator can never be mistaken for real data.
enum MockData {

    // MARK: - Single nights

    /// A good night with full Apple Watch staging.
    static let goodNight = makeNight(
        daysAgo: 0,
        asleep: 452, inBed: 488,
        core: 244, deep: 82, rem: 126,
        awake: 36, wakes: 2,
        latency: 12,
        hr: 58, minHR: 51, hrv: 64, resp: 14.2, spo2: 96.8, tempDelta: -0.08,
        hrv7: 61, debt: 95, workoutHours: 6.5, exercise: 42
    )

    /// A poor night: short, fragmented, low HRV, late workout. This is the case
    /// the rule-based engine has the most to say about.
    static let poorNight = makeNight(
        daysAgo: 0,
        asleep: 318, inBed: 402,
        core: 208, deep: 34, rem: 76,
        awake: 84, wakes: 7,
        latency: 41,
        hr: 67, minHR: 61, hrv: 38, resp: 16.1, spo2: 94.9, tempDelta: 0.61,
        hrv7: 60, debt: 340, workoutHours: 1.2, exercise: 78
    )

    /// A night from a source with no stage breakdown — iPhone sleep schedule or
    /// a third-party tracker. Exercises the `hasStageBreakdown == false` path,
    /// which is easy to forget and looks broken when it regresses.
    static var unstagedNight: SleepNightFeatures {
        var night = makeNight(
            daysAgo: 0,
            asleep: 401, inBed: 436,
            core: 0, deep: 0, rem: 0,
            awake: 35, wakes: 3,
            latency: nil,
            hr: 60, minHR: 54, hrv: nil, resp: nil, spo2: nil, tempDelta: nil,
            hrv7: nil, debt: 150, workoutHours: nil, exercise: nil
        )
        night = night.withUnspecifiedSleep(401)
        return night
    }

    // MARK: - History

    /// 30 nights of plausibly noisy history, newest last.
    ///
    /// Deterministically generated from a seeded generator so previews and
    /// snapshot comparisons are stable across runs — random previews that shift
    /// every rebuild make chart regressions impossible to spot.
    static let history: [SleepNightFeatures] = {
        var rng = SeededGenerator(seed: 20_260_807)
        return (0..<30).reversed().map { daysAgo -> SleepNightFeatures in
            // Weekends drift later and longer.
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            let isWeekend = Calendar.current.isDateInWeekend(date)

            let baseAsleep = isWeekend ? 455.0 : 405.0
            let asleep = baseAsleep + rng.nextDouble(in: -55...55)
            let inBed = asleep + rng.nextDouble(in: 20...70)
            let deep = asleep * rng.nextDouble(in: 0.11...0.21)
            let rem = asleep * rng.nextDouble(in: 0.17...0.26)
            let core = asleep - deep - rem
            let awake = inBed - asleep
            let wakes = Int(rng.nextDouble(in: 0...6).rounded())

            return makeNight(
                daysAgo: daysAgo,
                asleep: asleep, inBed: inBed,
                core: core, deep: deep, rem: rem,
                awake: awake, wakes: wakes,
                latency: rng.nextDouble(in: 6...34),
                hr: rng.nextDouble(in: 54...66),
                minHR: rng.nextDouble(in: 48...58),
                hrv: rng.nextDouble(in: 42...78),
                resp: rng.nextDouble(in: 13...16),
                spo2: rng.nextDouble(in: 94...98),
                tempDelta: rng.nextDouble(in: -0.4...0.5),
                hrv7: rng.nextDouble(in: 52...66),
                debt: max(0, rng.nextDouble(in: -50...420)),
                workoutHours: rng.nextDouble(in: 0.8...9),
                exercise: rng.nextDouble(in: 0...95)
            )
        }
    }()

    /// Last 7 nights of `history`.
    static var recentWeek: [SleepNightFeatures] { Array(history.suffix(7)) }

    // MARK: - Derived mocks

    static let goodInsight = SleepInsight(
        summary: "Solid night — 7h 32m with strong deep sleep.",
        likelyCause: nil,
        actionableTip: "Whatever you did yesterday, repeat it. Same bedtime tonight.",
        confidence: .high
    )

    static let poorInsight = SleepInsight(
        summary: "Rough night — 5h 18m and fragmented.",
        likelyCause: "Deep sleep was 34m, well below your usual. Your workout ended about 1h before bed, which keeps core body temperature up.",
        actionableTip: "Try to finish hard training at least 3h before bed tonight.",
        confidence: .medium
    )

    static var snapshot: SleepSnapshot {
        SleepSnapshot(
            features: goodNight,
            score: SleepScore.compute(for: goodNight, goalMinutes: 480),
            insight: goodInsight,
            goalMinutes: 480,
            sleepIntelligencePercent: 84,
            sleepIntelligenceBand: "Excellent"
        )
    }

    /// The habitual night length the autopilot would measure from `history`.
    ///
    /// Computed over the same trailing window the engine uses, not over all
    /// of `history`: the two Tonight snapshots below need a plan that is
    /// *definitely* holding and one that is *definitely* shifting, and a
    /// median taken over a different window would only land inside the
    /// deadband by luck. Matching the window makes the holding case exact --
    /// asking for precisely the habit produces a zero shift by construction.
    private static var habitualSleepMinutes: Double {
        let recent = history.sorted { $0.date < $1.date }.suffix(SleepAutopilot.window)
        return Statistics.median(recent.compactMap { TrendEngine.Metric.duration.value(from: $0) }) ?? 420
    }

    /// Snapshot with tonight's plan and tomorrow's range filled in, for the
    /// Tonight widget and complication previews.
    ///
    /// Runs the real engines over the mock history rather than hard-coding
    /// strings, so a preview shows what the widget will actually render. The
    /// phone fills these fields the same way -- see
    /// `SleepDataCoordinator.publishSnapshot`.
    static var tonightSnapshot: SleepSnapshot {
        makeTonightSnapshot(sleepNeedMinutes: habitualSleepMinutes + 45, sleepDebtMinutes: 96)
    }

    /// The other half of the plan: nothing worth changing tonight. Worth its
    /// own preview because it is a different tint and different copy, and
    /// because "hold" is the outcome most nights should produce.
    static var holdingTonightSnapshot: SleepSnapshot {
        makeTonightSnapshot(sleepNeedMinutes: habitualSleepMinutes, sleepDebtMinutes: 0)
    }

    private static func makeTonightSnapshot(sleepNeedMinutes: Double, sleepDebtMinutes: Double) -> SleepSnapshot {
        var result = snapshot
        if let plan = SleepAutopilot.plan(
            nights: history,
            sleepNeedMinutes: sleepNeedMinutes,
            sleepDebtMinutes: sleepDebtMinutes
        ) {
            result.tonightTargetLabel = plan.targetRangeLabel
            result.tonightTargetNote = plan.sentence
            result.isTonightTargetHolding = plan.isHolding
        }
        if let forecast = UncertaintyForecast.forecastAll(nights: history).first {
            result.tomorrowRangeLabel = forecast.rangeLabel
        }
        return result
    }

    /// Snapshot with badge fields filled in, for the badge widget previews.
    static var snapshotWithBadges: SleepSnapshot {
        var result = snapshot
        let achievements = AchievementEngine.evaluate(
            nights: history,
            goalMinutes: 420,
            journalTaggedNights: 9,
            napCount: 4,
            regularityIndex: 74
        )
        result.badgesUnlocked = achievements.filter(\.isUnlocked).count
        result.badgesTotal = achievements.count
        if let headline = AchievementEngine.headline(achievements) {
            result.badgeTitle = headline.title
            result.badgeSymbol = headline.symbol
            result.badgeTier = headline.tier.rawValue
        }
        if let next = AchievementEngine.nextUp(achievements) {
            result.nextBadgeTitle = next.title
            result.nextBadgeProgress = next.progress
        }
        return result
    }

    static var poorSnapshot: SleepSnapshot {
        SleepSnapshot(
            features: poorNight,
            score: SleepScore.compute(for: poorNight, goalMinutes: 480),
            insight: poorInsight,
            goalMinutes: 480,
            sleepIntelligencePercent: 41,
            sleepIntelligenceBand: "Fair"
        )
    }

    // MARK: - Derived inputs for the Today screen

    static let todayStrain = StrainScore.compute(
        zoneMinutes: [.light: 95, .moderate: 42, .vigorous: 26, .hard: 11],
        activeEnergyKcal: 612,
        hasHeartRateCoverage: true
    )

    static let yesterdayStrain = StrainScore.compute(
        zoneMinutes: [.light: 120, .moderate: 55, .vigorous: 38, .hard: 22, .maximum: 6],
        activeEnergyKcal: 890,
        hasHeartRateCoverage: true
    )

    /// A plausible waking day of hourly heart rate.
    ///
    /// Shaped rather than random: quiet morning, a midday session that spikes,
    /// an afternoon plateau, an evening wind-down. A flat noise field would make
    /// the body battery curve look broken even though the maths was right.
    static func hourlyHeartRate(wakeTime: Date) -> [(date: Date, bpm: Double)] {
        let profile: [Double] = [
            62, 68, 71, 74, 70,      // morning
            88, 132, 118, 84,        // midday session and cooldown
            76, 73, 71, 74, 78,      // afternoon
            70, 66, 63, 61           // evening
        ]
        let elapsed = Date.now.timeIntervalSince(wakeTime) / 3600
        let hours = max(1, min(profile.count, Int(elapsed)))

        return (0..<hours).map { index in
            (date: wakeTime.addingTimeInterval(Double(index + 1) * 3600),
             bpm: profile[index])
        }
    }

    // MARK: - Builder

    private static func makeNight(
        daysAgo: Int,
        asleep: Double, inBed: Double,
        core: Double, deep: Double, rem: Double,
        awake: Double, wakes: Int,
        latency: Double?,
        hr: Double?, minHR: Double?, hrv: Double?, resp: Double?, spo2: Double?, tempDelta: Double?,
        hrv7: Double?, debt: Double?, workoutHours: Double?, exercise: Double?
    ) -> SleepNightFeatures {
        let calendar = Calendar.current
        let wake = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
        let wakeTime = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: wake) ?? wake
        let bedtime = wakeTime.addingTimeInterval(-inBed * 60)

        return SleepNightFeatures(
            date: calendar.startOfDay(for: wakeTime),
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: inBed,
            timeAsleepMinutes: asleep,
            sleepEfficiencyPercent: inBed > 0 ? min(100, asleep / inBed * 100) : 0,
            coreMinutes: core,
            deepMinutes: deep,
            remMinutes: rem,
            unspecifiedAsleepMinutes: 0,
            awakeMinutes: awake,
            wakeCount: wakes,
            sleepLatencyMinutes: latency,
            avgHeartRate: hr,
            minHeartRate: minHR,
            // A plausible true RHR a few bpm above the sleep-window low,
            // rather than reusing minHR outright -- they're different
            // signals in reality, and mock data pretending they're identical
            // would hide a mismatch other code might have.
            restingHeartRate: minHR.map { $0 + 4 },
            avgHRV: hrv,
            avgRespiratoryRate: resp,
            avgSpO2: spo2,
            wristTempDeltaC: tempDelta,
            hrv7DayAvg: hrv7,
            sleepDebtMinutes: debt,
            lastWorkoutHoursBeforeBed: workoutHours,
            exerciseMinutesPreviousDay: exercise,
            sourceName: "Mock Data",
            isMock: true
        )
    }
}

private extension SleepNightFeatures {
    /// Rebuilds the value with all sleep filed as unspecified — the shape you
    /// get from a non-staging source.
    func withUnspecifiedSleep(_ minutes: Double) -> SleepNightFeatures {
        SleepNightFeatures(
            date: date, bedtime: bedtime, wakeTime: wakeTime,
            timeInBedMinutes: timeInBedMinutes,
            timeAsleepMinutes: minutes,
            sleepEfficiencyPercent: sleepEfficiencyPercent,
            coreMinutes: 0, deepMinutes: 0, remMinutes: 0,
            unspecifiedAsleepMinutes: minutes,
            awakeMinutes: awakeMinutes, wakeCount: wakeCount,
            sleepLatencyMinutes: sleepLatencyMinutes,
            avgHeartRate: avgHeartRate, minHeartRate: minHeartRate, avgHRV: avgHRV,
            avgRespiratoryRate: avgRespiratoryRate, avgSpO2: avgSpO2,
            wristTempDeltaC: wristTempDeltaC,
            hrv7DayAvg: hrv7DayAvg, sleepDebtMinutes: sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: exerciseMinutesPreviousDay,
            sourceName: "iPhone", isMock: true
        )
    }
}

// `SeededGenerator` (SplitMix64) lives in Shared/SeededGenerator.swift --
// shared with `Statistics.pairedBootstrapCI` so there's one canonical
// deterministic PRNG rather than two copies drifting apart.
