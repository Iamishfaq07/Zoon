import Foundation

/// How much the stage breakdown for a night is worth believing.
///
/// `SleepNightFeatures.hasStageBreakdown` answers a different question: it
/// says stages *exist*, not that they mean anything. An Apple Watch
/// classifier, a third-party tracker and a schedule typed in by hand all set
/// that flag identically, and the app has been showing Deep and REM minutes
/// from all three in the same type at the same weight.
///
/// **The trap this type exists to avoid.** The obvious implementation reads
/// `SleepNightFeatures.sourceBundleIdentifier` and calls
/// `SourcePriority.classify`. That is wrong, and wrong in the most damaging
/// direction. `classify` separates an Apple Watch from an iPhone using
/// `hardwareVersion` -- the `productType` string, "Watch7,4" -- because both
/// write under the same `com.apple.health` bundle. Without it every Apple
/// Watch night falls through to `.phoneOrManual`, and the app would tell
/// people their best stage data is their least trustworthy. So the
/// classification happens once in `SleepSessionBuilder`, where the sample's
/// `sourceRevision` is still in scope, and is carried forward rather than
/// re-derived downstream from data that cannot answer the question.
///
/// **What this is not.** None of these levels means clinically accurate.
/// Every one of them is a consumer device inferring stages from movement and
/// heart rate, which is not what a sleep laboratory measures, and `.high`
/// means "as good as this category gets" rather than "correct". Nothing here
/// should be rendered as a validation claim.
enum StageTrust: Int, Comparable, Sendable, Codable, Hashable {

    /// No stage breakdown at all. Missing, not zero, and not poor quality
    /// either -- there is simply nothing to grade.
    case unstaged = 0

    /// A phone schedule or a manual entry. These sources do not observe
    /// sleep; where stages appear at all they were inferred from a bedtime,
    /// not measured from a body.
    case inferred = 1

    /// A recognised third-party wearable. A real sensor on a real wrist,
    /// with a classifier this app cannot see and cannot check.
    case wearable = 2

    /// Apple Watch, Apple's own write. The staging this app is built around,
    /// and still a consumer classifier rather than a laboratory.
    case watch = 3

    static func < (lhs: StageTrust, rhs: StageTrust) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The grade for a night, from the priority the builder recorded.
    ///
    /// - Parameters:
    ///   - priority: what `SleepSessionBuilder` classified the winning sleep
    ///     source as, or `nil` for a night assembled before this was carried.
    ///   - hasStages: whether the night actually has a stage breakdown.
    ///     Without one there is nothing to trust at any level, whatever the
    ///     source was.
    static func grade(priority: SourcePriority?, hasStages: Bool) -> StageTrust {
        guard hasStages else { return .unstaged }
        switch priority {
        case .appleWatch: return .watch
        case .thirdPartyWearable: return .wearable
        case .phoneOrManual: return .inferred
        // A night from before the priority was carried. It has stages, so
        // something wrote them, but nothing here knows what -- and guessing
        // upward would be the failure this type exists to prevent. The
        // honest floor is the level that promises least.
        case nil: return .inferred
        }
    }

    /// Whether stage figures should be presented as measurements at all.
    ///
    /// False for `.inferred`, where "Deep 1h 12m" is a number derived from a
    /// bedtime and printing it in the same type as a measured one is the
    /// "estimated is not measured" failure.
    var supportsStageFigures: Bool { self >= .wearable }

    /// A short phrase for the provenance line under a stage figure. Present
    /// tense, about the source, and never about accuracy.
    var provenance: String {
        switch self {
        case .unstaged: "No stage data for this night"
        case .inferred: "Stages inferred from a schedule, not measured"
        case .wearable: "Stages from your wearable's own classifier"
        case .watch: "Stages from Apple Watch"
        }
    }
}
