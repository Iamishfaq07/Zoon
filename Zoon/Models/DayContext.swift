import Foundation

/// Everything the Today screen needs, computed once per refresh.
///
/// One value rather than a dozen published properties on the coordinator: the
/// screen should never be able to render a recovery score from this morning
/// beside a body battery from twenty minutes ago. Swapping a single immutable
/// struct makes a torn read impossible.
struct DayContext: Equatable {

    let night: SleepNightFeatures
    let insight: SleepInsight

    let recovery: RecoveryScore
    let sleepNeed: SleepNeed
    let learnedSleepNeed: LearnedSleepNeed
    /// Tonight's planning inputs, **as of now**. Not `sleepNeed`: that
    /// assesses last night against the debt carried *into* it and the day
    /// before it. This carries the debt with last night applied, today's
    /// strain and today's naps. See `SleepPlanningInputs.asOfNow`.
    let tonightPlanning: SleepPlanningInputs
    let sleepScore: SleepScore
    let sleepIntelligence: SleepIntelligenceScore
    let strain: StrainScore
    let bodyBattery: BodyBattery
    let vitals: VitalsStatus
    let hrvStatus: HRVStatus
    let chronotype: Chronotype
    let regularity: SleepRegularity
    let healthRadar: HealthRadar
    /// Habitual sleep window. Nil until there is any history at all.
    let bodyClock: BodyClock?
    /// Hourly heart rate for today -- also drives the body battery curve.
    /// Carried through so views (e.g. the hypnogram's HR overlay) can reuse
    /// it rather than each running their own HealthKit query.
    let hourlyHeartRate: [(date: Date, bpm: Double)]
    /// Hourly cognitive-energy amplitude from last night's HRV, HR dip,
    /// and REM/Deep mix. Shape still comes from `EnergyForecast`; this is
    /// how high the peak sits and how deep the slump goes.
    let cognitiveEnergy: CognitiveEnergyCurve
    /// Textbook 24-hour SRI. Not shown as the on-screen regularity number
    /// — see `SleepRegularity` — and carried so Regularity's detail screen
    /// and a clinician export can quote the academic figure without
    /// recomputing it from a different window.
    let academicSleepRegularity: SleepRegularityIndex

    /// True when this is synthetic data (Simulator / previews).
    var isMock: Bool { night.isMock }

    /// A copy with a different night, everything else carried over.
    ///
    /// Exists so nothing outside this file has to spell out the full
    /// initialiser. A memberwise call in a preview is a line that silently
    /// needs editing every time a field is added here — which has already
    /// broken the build once.
    func replacing(night: SleepNightFeatures) -> DayContext {
        DayContext(
            night: night,
            insight: insight,
            recovery: recovery,
            sleepNeed: sleepNeed,
            learnedSleepNeed: learnedSleepNeed,
            tonightPlanning: tonightPlanning,
            sleepScore: sleepScore,
            sleepIntelligence: sleepIntelligence,
            strain: strain,
            bodyBattery: bodyBattery,
            vitals: vitals,
            hrvStatus: hrvStatus,
            chronotype: chronotype,
            regularity: regularity,
            healthRadar: healthRadar,
            bodyClock: bodyClock,
            hourlyHeartRate: hourlyHeartRate,
            cognitiveEnergy: cognitiveEnergy,
            academicSleepRegularity: academicSleepRegularity
        )
    }

    /// Tonight's target bedtime: your usual wake time, minus tonight's need.
    ///
    /// Lives here rather than in the view that draws it because two things now
    /// depend on it — the countdown card and the scheduled reminder — and a
    /// notification that fires at a different time from the one on screen is
    /// worse than no notification.
    ///
    /// Derived from the user's own wake pattern rather than an alarm they have
    /// to configure: the data is already here, and a setting you must fill in
    /// before the feature works is a setting most people never fill in.
    ///
    /// Resolved through `ResolvedSleepEpisode.window`, so a bedtime that has
    /// passed stays tonight's until the wake it was planning for. This used
    /// to anchor on "tomorrow" relative to now, which after midnight is the
    /// morning after next: at 00:30 the countdown read nearly a day.
    ///
    /// Prefer `SleepDataCoordinator.tonightEpisode()` where it is reachable:
    /// that also knows the person's own plans and the autopilot. This is the
    /// fallback it uses when neither applies.
    func targetBedtime(now: Date = .now, calendar: Calendar = .current) -> Date? {
        let wake = calendar.dateComponents([.hour, .minute], from: night.wakeTime)
        let wakeMinute = Double((wake.hour ?? 7) * 60 + (wake.minute ?? 0))
        return ResolvedSleepEpisode.window(
            bedMinute: wakeMinute - tonightPlanning.tonightNeedMinutes,
            wakeMinute: wakeMinute,
            containingOrAfter: now,
            calendar: calendar
        )?.start
    }

    /// The morning headline — what a user reads in two seconds.
    var headline: String {
        if recovery.isEstimate {
            return "Building your baseline"
        }
        switch recovery.band {
        case .high: return "You're recovered"
        case .moderate: return "Moderately recovered"
        case .low: return "You need to take it easy"
        }
    }
}

extension DayContext {
    static func == (lhs: DayContext, rhs: DayContext) -> Bool {
        lhs.night == rhs.night
            && lhs.recovery == rhs.recovery
            && lhs.bodyBattery == rhs.bodyBattery
            && lhs.strain == rhs.strain
            && lhs.regularity == rhs.regularity
            && lhs.healthRadar == rhs.healthRadar
    }
}
