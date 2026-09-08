import Foundation

/// Overnight count of Apple's sleep-apnea *category* events, if any.
///
/// Breathing disturbances (the quantity `FeatureExtractor` already reads as
/// `appleSleepingBreathingDisturbances`) are a 0...1 fraction plus Apple's
/// own elevated/not-elevated classifier. Sleep apnea *events* are a separate
/// `HKCategoryTypeIdentifier.sleepApneaEvent` stream, written only on
/// hardware that has the feature enabled (Series 9 / Ultra 2 and later,
/// iOS 18+). Most nights this is `nil`, and `nil` is not zero — it means
/// the category was not recorded, not that the person had no events.
///
/// Never presented as a diagnosis. The copy this type owns is a count and a
/// coverage note; anything clinical is Apple's notification, not Zoon's.
struct SleepApneaEventSummary: Hashable, Sendable {
    /// How many events landed inside the night's asleep intervals.
    let eventCount: Int
    /// Wall-clock span of the first and last event, if any.
    let firstEvent: Date?
    let lastEvent: Date?

    var isEmpty: Bool { eventCount == 0 }

    /// Non-diagnostic. A count is a count; "apnea" in the type name is
    /// Apple's identifier, not a claim Zoon is making about the person.
    var sentence: String {
        switch eventCount {
        case 0:
            "No sleep-apnea events were recorded for this night. That is a statement about what the watch wrote, not about whether breathing was undisturbed."
        case 1:
            "The watch recorded one sleep-apnea event overnight. Apple's own notification, if any, is the clinical surface — Zoon only counts what was written."
        default:
            "The watch recorded \(eventCount) sleep-apnea events overnight. Apple's own notification, if any, is the clinical surface — Zoon only counts what was written."
        }
    }
}
