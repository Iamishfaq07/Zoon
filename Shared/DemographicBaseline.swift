import Foundation

/// Expected stage mix given age, sex and (optionally) BMI.
///
/// Deep sleep declines with age. A 55-year-old whose night is 14% deep is
/// typical; the same fraction at 25 is a shortfall. Scoring everyone against
/// a single adult target therefore penalises older sleepers for physiology
/// they cannot change, which is the exact failure this type exists to stop.
///
/// ## What this is and is not
///
/// This is a **population prior**, not a diagnosis and not a personal
/// baseline. Once Zoon has enough of *this person's* nights, `RollingBaseline`
/// is the authority and this prior only remains as a first-weeks stand-in
/// (and as the denominator that keeps a deep-sleep *score* from calling a
/// normal age-related mix "poor").
///
/// Sex is used only where the literature actually splits (typical deep-sleep
/// fraction is a touch higher in women across adulthood). BMI nudges the
/// prior when it is in the obese range, because population studies associate
/// that range with a modestly lower deep-sleep fraction — it is a small
/// correction, never a judgement, and it is ignored when BMI is missing.
///
/// The numbers below are rounded, adult, non-clinical summaries of Ohayon
/// et al. (2004) and subsequent meta-analyses. They are not medical advice.
struct DemographicBaseline: Hashable, Sendable {

    enum Sex: String, Codable, Sendable {
        case female, male, unspecified
    }

    /// Whole years. Values outside 18...90 are clamped rather than rejected:
    /// a wrong age is still closer than no age, and the curve is already
    /// flat at the ends.
    var ageYears: Int
    var sex: Sex
    /// kg / m². `nil` leaves the prior unadjusted.
    var bodyMassIndex: Double?

    /// Expected deep-sleep fraction of total sleep, 0...1.
    var expectedDeepFraction: Double {
        let age = Double(min(90, max(18, ageYears)))
        // ~20% at 20, declining ~2 percentage points per decade after 30.
        let afterThirty = max(0, age - 30)
        var fraction = 0.20 - 0.002 * afterThirty
        switch sex {
        case .female: fraction += 0.01
        case .male, .unspecified: break
        }
        if let bmi = bodyMassIndex, bmi >= 30 {
            fraction -= 0.015
        }
        return min(0.25, max(0.08, fraction))
    }

    /// Expected REM fraction of total sleep, 0...1. REM is much more stable
    /// across adulthood than deep; the age slope here is shallow on purpose.
    var expectedRemFraction: Double {
        let age = Double(min(90, max(18, ageYears)))
        var fraction = 0.22 - 0.0004 * max(0, age - 30)
        if sex == .female { fraction += 0.005 }
        return min(0.28, max(0.16, fraction))
    }

    /// How this night's deep-sleep *minutes* sit against the prior, as a
    /// ratio. 1.0 is exactly typical for this demographic; 0.7 is 30% below
    /// the prior (not "30% of the night was deep").
    ///
    /// Returns `nil` when the night has no stage breakdown — there is
    /// nothing honest to compare.
    func deepSleepRatio(asleepMinutes: Double, deepMinutes: Double) -> Double? {
        guard asleepMinutes > 0, deepMinutes >= 0 else { return nil }
        let expected = expectedDeepFraction * asleepMinutes
        guard expected > 0 else { return nil }
        return deepMinutes / expected
    }

    /// A score contribution in 0...1 that refuses to punish a night for
    /// matching its demographic prior. A 1.0 means at-or-above typical;
    /// 0.0 means deep sleep was absent. Between those, the ratio is
    /// clamped so a *surplus* of deep sleep cannot inflate a recovery
    /// number — extra deep is not extra credit.
    func deepSleepScoreContribution(asleepMinutes: Double, deepMinutes: Double) -> Double? {
        guard let ratio = deepSleepRatio(asleepMinutes: asleepMinutes, deepMinutes: deepMinutes) else {
            return nil
        }
        return min(1, max(0, ratio))
    }
}
