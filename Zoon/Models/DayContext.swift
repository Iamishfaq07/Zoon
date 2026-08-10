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
    let sleepScore: SleepScore
    let strain: StrainScore
    let bodyBattery: BodyBattery
    let vitals: VitalsStatus
    let hrvStatus: HRVStatus
    let chronotype: Chronotype
    let regularity: SleepRegularity
    let healthRadar: HealthRadar
    let cardiovascularAge: CardiovascularAge?
    /// Habitual sleep window. Nil until there is any history at all.
    let bodyClock: BodyClock?

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
            sleepScore: sleepScore,
            strain: strain,
            bodyBattery: bodyBattery,
            vitals: vitals,
            hrvStatus: hrvStatus,
            chronotype: chronotype,
            regularity: regularity,
            healthRadar: healthRadar,
            cardiovascularAge: cardiovascularAge,
            bodyClock: bodyClock
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
    func targetBedtime(now: Date = .now, calendar: Calendar = .current) -> Date? {
        let wake = calendar.dateComponents([.hour, .minute], from: night.wakeTime)

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let wakeTomorrow = calendar.date(
                  bySettingHour: wake.hour ?? 7,
                  minute: wake.minute ?? 0,
                  second: 0,
                  of: tomorrow
              )
        else { return nil }

        return wakeTomorrow.addingTimeInterval(-sleepNeed.totalNeedMinutes * 60)
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
