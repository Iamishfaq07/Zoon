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

    /// True when this is synthetic data (Simulator / previews).
    var isMock: Bool { night.isMock }

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
