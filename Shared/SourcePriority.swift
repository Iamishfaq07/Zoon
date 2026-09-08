import Foundation

/// Which writer of a sleep sample should win when two overlap.
///
/// `SleepSessionBuilder` already refuses to *merge* rival sources — two
/// trackers disagree about stage boundaries, and a union of them is a night
/// neither device reported. What it still has to do is pick a winner. Until
/// now that was a quality score with a small provenance bonus for
/// `productType != nil` (Apple Watch). The bonus is right *on average* and
/// wrong when the Watch sample is the broken one, which is why quality still
/// dominates.
///
/// This type is the explicit ladder the builder consults as that bonus,
/// instead of a boolean "has a productType". Hardware version strings that
/// contain `"Watch"` are Priority 1; recognised third-party wearables are
/// Priority 2; phone-only, manual, and everything else is Priority 3.
///
/// A higher priority is a *tie-break*, never a veto. A Watch sample that
/// spans 20 hours still loses to a 7-hour Garmin night on quality.
enum SourcePriority: Int, Comparable, Sendable {
    case appleWatch = 1
    case thirdPartyWearable = 2
    case phoneOrManual = 3

    static func < (lhs: SourcePriority, rhs: SourcePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Smaller raw value is higher trust. Mapped onto the 0...1 bonus
    /// `SleepSessionBuilder.qualityScore` already multiplies by 0.5.
    var provenanceBonus: Double {
        switch self {
        case .appleWatch: 1.0
        case .thirdPartyWearable: 0.45
        case .phoneOrManual: 0
        }
    }

    /// - Parameters:
    ///   - hardwareVersion: `HKDevice.hardwareVersion` or
    ///     `HKSourceRevision.productType` (Watch7,4 / iPhone15,2 / …).
    ///   - bundleIdentifier: the sample's source bundle.
    ///   - sourceName: display name, used only as a last-resort brand match.
    static func classify(
        hardwareVersion: String?,
        bundleIdentifier: String?,
        sourceName: String?
    ) -> SourcePriority {
        if let hardwareVersion, hardwareVersion.localizedCaseInsensitiveContains("Watch") {
            return .appleWatch
        }
        // productType for a paired Apple Watch is values like "Watch7,4".
        // iPhone product types contain "iPhone", never "Watch".
        let wearable = WearableSource.identify(
            bundleIdentifier: bundleIdentifier,
            name: sourceName
        )
        switch wearable {
        case .apple:
            // Apple Health on iPhone, or an Apple Watch whose productType
            // was missing from this particular sample. Watch-with-productType
            // already returned above. Remaining Apple writes are phone
            // Sleep Schedule / iPhone motion — Priority 3.
            return .phoneOrManual
        case .unrecognised:
            return .phoneOrManual
        default:
            return .thirdPartyWearable
        }
    }
}
