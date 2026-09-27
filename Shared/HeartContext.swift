import Foundation

/// Where a person's heart numbers sit against people of the same age and
/// sex.
///
/// Everything else in Zoon compares a person with their own history, and
/// for day-to-day judgements that stays right: HRV in particular varies so
/// much between people that one person's worrying number is another's
/// normal. This type answers a different, fair question that the personal
/// view cannot: "is my number unusual for someone like me?" It is shown as
/// context beside the personal view, never fed into a score.
///
/// Sources, all population studies of healthy adults:
///
/// - **Resting heart rate.** The American Heart Association's usual adult
///   range of 60 to 100 bpm. Quer et al., *PLOS ONE* 2020 (92,457 wearable
///   users): an average near 65 bpm, women a few beats higher than men, and
///   one person's normal differing from another's by up to 70 bpm.
/// - **HRV (SDNN).** Voss et al., *PLOS ONE* 2015 (1,906 adults, 5-minute
///   ECG): the average fell from about 50 ms at 25–34 to about 30 ms at
///   65–74. Apple Watch measures over about a minute, and shorter recordings
///   give lower SDNN, so its readings often sit below these figures.
/// - **Cardio fitness (VO2 max).** The FRIEND registry's treadmill reference
///   standards, Kaminsky et al., *Mayo Clinic Proceedings* 2015: the median
///   for each decade from 20 to 79, separately for men and women. Apple
///   Watch estimates VO2 max from walks and runs rather than measuring it.
enum HeartContext {

    enum Position: String, Hashable, Sendable {
        case below, typical, above

        var label: String {
            switch self {
            case .below: "Below typical"
            case .typical: "Typical"
            case .above: "Above typical"
            }
        }
    }

    /// One row of context: the person's value, where it sits, and the
    /// sentence that says so.
    struct Reading: Hashable, Sendable {
        let value: Double
        /// The population reference for this person: a range for resting
        /// heart rate, a typical value for HRV and VO2 max.
        let reference: ClosedRange<Double>
        let position: Position
        /// Whether a high value is the good direction (HRV, VO2 max) or the
        /// other way (resting heart rate).
        let higherIsFavourable: Bool
        let sentence: String
    }

    // MARK: - Resting heart rate

    /// The usual adult resting range, bpm.
    static let usualRestingRange: ClosedRange<Double> = 60...100

    static func restingHeartRate(_ bpm: Double, sex: DemographicBaseline.Sex) -> Reading {
        let rounded = Int(bpm.rounded())
        let position: Position
        let sentence: String
        switch bpm {
        case ..<40:
            position = .below
            sentence = "\(rounded) bpm is lower than almost all adults. It is common in endurance athletes; if you are not one and feel faint or dizzy, mention it to a doctor."
        case ..<60:
            position = .below
            sentence = "\(rounded) bpm is lower than most adults, which is common with regular exercise."
        case ...100:
            position = .typical
            sentence = "\(rounded) bpm is inside the usual adult range of 60 to 100 bpm."
        default:
            position = .above
            sentence = "\(rounded) bpm is above the usual adult resting range of 60 to 100 bpm. Illness, stress, caffeine and poor sleep can all raise it; if it stays high, mention it to a doctor."
        }
        let sexNote: String
        switch sex {
        case .female: sexNote = " Women's resting heart rate usually runs a few beats higher than men's."
        case .male: sexNote = " Men's resting heart rate usually runs a few beats lower than women's."
        case .unspecified: sexNote = ""
        }
        return Reading(
            value: bpm,
            reference: usualRestingRange,
            position: position,
            higherIsFavourable: false,
            sentence: sentence + sexNote
        )
    }

    // MARK: - HRV

    /// The average 5-minute SDNN for an age, ms, interpolated along the
    /// decline Voss et al. reported: about 50 ms up to 30, falling to about
    /// 30 ms at 70, and held flat beyond both ends of the studied range.
    static func typicalHRV(age: Int) -> Double {
        let clamped = Double(min(75, max(25, age)))
        guard clamped > 30 else { return 50 }
        return max(28, 50 - (clamped - 30) * 0.5)
    }

    /// Within this fraction of the age-typical value counts as typical. HRV
    /// is wide between people, so the band is wide on purpose.
    static let hrvTypicalFraction = 0.35

    static func heartRateVariability(_ ms: Double, age: Int) -> Reading {
        let typical = typicalHRV(age: age)
        let low = typical * (1 - hrvTypicalFraction)
        let high = typical * (1 + hrvTypicalFraction)
        let rounded = Int(ms.rounded())
        let typicalText = Int(typical.rounded())
        let position: Position
        let sentence: String
        if ms < low {
            position = .below
            sentence = "\(rounded) ms is below the \(typicalText) ms that studies find typical at \(age). That is common with Apple Watch, which measures over a shorter window, and HRV varies a lot between healthy people. Your own trend matters more."
        } else if ms > high {
            position = .above
            sentence = "\(rounded) ms is above the \(typicalText) ms that studies find typical at \(age). Regular exercise and good sleep tend to raise HRV."
        } else {
            position = .typical
            sentence = "\(rounded) ms is close to the \(typicalText) ms that studies find typical at \(age). HRV falls slowly with age, so this is a fair comparison."
        }
        return Reading(
            value: ms,
            reference: low...high,
            position: position,
            higherIsFavourable: true,
            sentence: sentence
        )
    }

    // MARK: - Cardio fitness

    /// FRIEND 2015 treadmill medians, mL/kg/min, by decade from 20–29 to
    /// 70–79.
    static let vo2MaxMedians: [DemographicBaseline.Sex: [Double]] = [
        .male: [48.0, 42.4, 37.8, 32.6, 28.2, 24.4],
        .female: [37.6, 30.9, 27.7, 24.4, 22.8, 20.8]
    ]

    /// "30–39". `nil` outside the registry's 20–79.
    static func decadeLabel(age: Int) -> String? {
        guard (20...79).contains(age) else { return nil }
        let start = age / 10 * 10
        return "\(start)–\(start + 9)"
    }

    /// The median for this age and sex. `nil` outside 20–79, and when sex
    /// is not set: the two tables differ by a quarter, and averaging them
    /// would be wrong for everybody.
    static func typicalVO2Max(age: Int, sex: DemographicBaseline.Sex) -> Double? {
        guard (20...79).contains(age), let medians = vo2MaxMedians[sex] else { return nil }
        return medians[(age - 20) / 10]
    }

    /// Within this fraction of the median counts as typical.
    static let vo2TypicalFraction = 0.10

    static func cardioFitness(_ vo2Max: Double, age: Int, sex: DemographicBaseline.Sex) -> Reading? {
        guard let median = typicalVO2Max(age: age, sex: sex), let decade = decadeLabel(age: age) else {
            return nil
        }
        let group = "\(sex == .female ? "women" : "men") aged \(decade)"
        let low = median * (1 - vo2TypicalFraction)
        let high = median * (1 + vo2TypicalFraction)
        let value = String(format: "%.1f", vo2Max)
        let medianText = String(format: "%.1f", median)
        let position: Position
        let sentence: String
        if vo2Max < low {
            position = .below
            sentence = "\(value) is below the middle for \(group), which is \(medianText). Brisk walking, running or cycling most days raises it within weeks."
        } else if vo2Max > high {
            position = .above
            sentence = "\(value) is above the middle for \(group), which is \(medianText). Higher cardio fitness is one of the strongest signs of long-term health."
        } else {
            position = .typical
            sentence = "\(value) is around the middle for \(group), which is \(medianText)."
        }
        return Reading(
            value: vo2Max,
            reference: low...high,
            position: position,
            higherIsFavourable: true,
            sentence: sentence
        )
    }
}
