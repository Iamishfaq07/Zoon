import Foundation

/// How much sleep the National Sleep Foundation's expert panel recommends at
/// a given age.
///
/// Source: Hirshkowitz et al., "National Sleep Foundation's sleep time
/// duration recommendations: methodology and results summary", *Sleep
/// Health* 1(1), 2015, reaffirmed by the NSF since. Two bands per age group:
///
/// - **Recommended**: what the panel agreed is appropriate for most people.
/// - **May be appropriate**: outside the recommendation but still within
///   what can be normal for some people. Beyond it the panel advised
///   against.
///
/// This is a population recommendation, not a measurement of anyone. Zoon
/// uses it for two things only: a starting goal that fits the person's age
/// before any history exists, and a sentence that says where a goal sits
/// against what experts suggest. The learned need (`LearnedSleepNeed`) stays
/// the authority once there are enough nights to learn from.
struct SleepNeedGuideline: Hashable, Sendable {

    /// Plain name of the age group, for sentences: "adults", "teenagers".
    let groupName: String
    let ages: ClosedRange<Int>
    /// Recommended nightly sleep, minutes.
    let recommendedMinutes: ClosedRange<Double>
    /// The wider "may be appropriate" band, minutes.
    let acceptableMinutes: ClosedRange<Double>

    /// The panel's table from school age up. Zoon's age pickers start at 16,
    /// but a restored backup or Health can hand over a younger age, and a
    /// wrong band is worse than the right one.
    static let bands: [SleepNeedGuideline] = [
        .init(groupName: "children aged 6 to 13", ages: 6...13, recommendedHours: 9...11, acceptableHours: 7...12),
        .init(groupName: "teenagers", ages: 14...17, recommendedHours: 8...10, acceptableHours: 7...11),
        .init(groupName: "young adults", ages: 18...25, recommendedHours: 7...9, acceptableHours: 6...11),
        .init(groupName: "adults", ages: 26...64, recommendedHours: 7...9, acceptableHours: 6...10),
        .init(groupName: "adults over 65", ages: 65...130, recommendedHours: 7...8, acceptableHours: 5...9)
    ]

    init(groupName: String, ages: ClosedRange<Int>, recommendedHours: ClosedRange<Double>, acceptableHours: ClosedRange<Double>) {
        self.groupName = groupName
        self.ages = ages
        self.recommendedMinutes = (recommendedHours.lowerBound * 60)...(recommendedHours.upperBound * 60)
        self.acceptableMinutes = (acceptableHours.lowerBound * 60)...(acceptableHours.upperBound * 60)
    }

    /// The band for an age, or `nil` when no age is known or it is outside
    /// the table.
    static func forAge(_ age: Int?) -> SleepNeedGuideline? {
        guard let age else { return nil }
        return bands.first { $0.ages.contains(age) }
    }

    /// The middle of the recommended range, rounded to the quarter hour: a
    /// starting goal of 8 hours for adults, 9 for teenagers and 7½ over 65.
    var suggestedGoalMinutes: Double {
        let middle = (recommendedMinutes.lowerBound + recommendedMinutes.upperBound) / 2
        return (middle / 15).rounded() * 15
    }

    /// "7–9 hours".
    var recommendedText: String {
        Self.hoursRange(recommendedMinutes)
    }

    /// "For adults, 7–9 hours a night is recommended."
    var sentence: String {
        "For \(groupName), \(recommendedText) a night is recommended."
    }

    enum Fit: Hashable, Sendable {
        case withinRecommended
        /// Below the recommendation, still inside "may be appropriate".
        case belowRecommended
        case aboveRecommended
        /// Below even the "may be appropriate" band.
        case wellBelow
        case wellAbove
    }

    func fit(_ minutes: Double) -> Fit {
        if recommendedMinutes.contains(minutes) { return .withinRecommended }
        if minutes < acceptableMinutes.lowerBound { return .wellBelow }
        if minutes > acceptableMinutes.upperBound { return .wellAbove }
        return minutes < recommendedMinutes.lowerBound ? .belowRecommended : .aboveRecommended
    }

    /// One plain sentence about where a goal sits against the
    /// recommendation. Never says "wrong": plenty of people genuinely need
    /// a little less or more, which is what the wider band exists for.
    func goalSentence(goalMinutes: Double) -> String {
        let goal = SleepNightFeatures.formatMinutes(goalMinutes)
        switch fit(goalMinutes) {
        case .withinRecommended:
            return "Your goal of \(goal) is inside the \(recommendedText) recommended for \(groupName)."
        case .belowRecommended:
            return "Your goal of \(goal) is a little under the \(recommendedText) recommended for \(groupName). Some people do need less."
        case .aboveRecommended:
            return "Your goal of \(goal) is a little over the \(recommendedText) recommended for \(groupName). Some people do need more."
        case .wellBelow:
            return "Your goal of \(goal) is well under the \(recommendedText) recommended for \(groupName). Consider raising it."
        case .wellAbove:
            return "Your goal of \(goal) is well over the \(recommendedText) recommended for \(groupName). If you need this much and still feel tired, it is worth mentioning to a doctor."
        }
    }

    static func hoursRange(_ range: ClosedRange<Double>) -> String {
        "\(hours(range.lowerBound))–\(hours(range.upperBound)) hours"
    }

    /// "7", "7½".
    private static func hours(_ minutes: Double) -> String {
        let whole = Int(minutes / 60)
        let remainder = minutes - Double(whole) * 60
        return remainder >= 15 ? "\(whole)½" : "\(whole)"
    }
}
