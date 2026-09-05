import Foundation

/// Which device or app wrote a night into Apple Health.
///
/// ## Why recognising a brand changes almost nothing
///
/// This type exists to put a name on a source, and for very little else.
/// What a given watch can actually measure is **observed** from the data it
/// has written -- see `SourceCoverage` -- never assumed from its brand.
///
/// That distinction is the whole design. A table saying "Garmin provides
/// HRV" would be wrong for some models, wrong after a firmware update, wrong
/// for a user who has that permission switched off in Garmin Connect, and
/// wrong in a way nobody would notice: the app would explain a metric it
/// never actually receives. Measuring what arrived is true by construction
/// and repairs itself when the situation changes.
///
/// So a recognised brand buys exactly two things: a tidier name than the
/// bundle identifier, and copy that can say "your Garmin" instead of "your
/// device". An unrecognised source loses the wording and nothing else --
/// every capability decision downstream is identical.
enum WearableSource: Hashable, Sendable {

    case apple
    case garmin
    case oura
    case whoop
    case fitbit
    case withings
    case polar
    case autoSleep
    case sleepCycle
    case pillow
    /// Anything not in the list above, carrying whatever name HealthKit
    /// reported. Not a failure state: see the type's own doc comment.
    case unrecognised(name: String)

    /// Bundle-identifier prefixes, matched case-insensitively.
    ///
    /// Prefixes rather than exact identifiers because vendors ship more than
    /// one bundle (companion apps, regional builds, watch extensions) and an
    /// exact match would quietly fall through to `unrecognised` on a rename.
    /// Being wrong here costs a display name, so a loose match is the right
    /// trade.
    private static let prefixes: [(prefix: String, source: WearableSource)] = [
        ("com.apple.health", .apple),
        ("com.apple.Health", .apple),
        ("com.garmin", .garmin),
        ("com.ouraring", .oura),
        ("com.whoop", .whoop),
        ("com.fitbit", .fitbit),
        ("com.withings", .withings),
        ("fi.polar", .polar),
        ("com.tantsissa", .autoSleep),
        ("com.northcube", .sleepCycle),
        ("com.neybox", .pillow)
    ]

    /// Identifies a source from what HealthKit reported about it.
    ///
    /// The bundle identifier is tried first because it is stable; the name is
    /// a fallback for rows written before Zoon recorded identifiers, and for
    /// restored backups where only the name survived.
    static func identify(bundleIdentifier: String?, name: String?) -> WearableSource {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            let lowered = bundleIdentifier.lowercased()
            for entry in prefixes where lowered.hasPrefix(entry.prefix.lowercased()) {
                return entry.source
            }
        }
        if let name, !name.isEmpty {
            let lowered = name.lowercased()
            // Deliberately narrow: these are brand words unlikely to appear
            // in an unrelated app's name. "Health" and "Sleep" are not here
            // for that reason -- half the App Store would match.
            let byName: [(needle: String, source: WearableSource)] = [
                ("garmin", .garmin), ("oura", .oura), ("whoop", .whoop),
                ("fitbit", .fitbit), ("withings", .withings), ("polar", .polar),
                ("autosleep", .autoSleep), ("sleep cycle", .sleepCycle),
                ("pillow", .pillow), ("apple watch", .apple), ("iphone", .apple)
            ]
            for entry in byName where lowered.contains(entry.needle) {
                return entry.source
            }
            return .unrecognised(name: name)
        }
        return .unrecognised(name: "Unknown source")
    }

    /// What to call it on screen.
    ///
    /// An unrecognised source shows the name HealthKit gave, which is
    /// usually the app's own display name and perfectly readable.
    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .garmin: "Garmin"
        case .oura: "Oura"
        case .whoop: "Whoop"
        case .fitbit: "Fitbit"
        case .withings: "Withings"
        case .polar: "Polar"
        case .autoSleep: "AutoSleep"
        case .sleepCycle: "Sleep Cycle"
        case .pillow: "Pillow"
        case .unrecognised(let name): name
        }
    }

    /// A possessive for copy: "your Garmin", "your Apple Watch".
    ///
    /// Falls back to "your device" rather than "your Sleep Tracker Pro",
    /// which reads like a brand endorsement Zoon has no business making.
    var possessivePhrase: String {
        switch self {
        case .unrecognised: "your device"
        default: "your \(displayName)"
        }
    }

    var isRecognised: Bool {
        if case .unrecognised = self { return false }
        return true
    }

    /// True for sources whose data Apple itself produces.
    ///
    /// Used only to explain why an Apple-exclusive quantity is missing --
    /// wrist temperature has no equivalent from a third-party watch, and
    /// telling someone their Garmin "isn't providing" it would imply a
    /// setting they could change.
    var isApple: Bool { self == .apple }
}
