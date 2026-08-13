import Foundation
import SwiftData

/// A sleep session HealthKit reported that was **not** selected as a night's
/// main sleep -- a nap, a second sleep block, or (in a split/biphasic
/// schedule) a session that's arguably the primary one but lost the pick.
///
/// `SleepDataCoordinator.processSessions` keeps exactly one `SleepSession`
/// per wake date as `SleepNightRecord`; everything else it builds was
/// previously discarded. That's the gap this closes: a HealthKit-detected
/// 38-minute nap now survives to disk instead of vanishing between session
/// building and persistence. `SleepNightRecord` itself is untouched -- this
/// is a new, additive table, so existing history needs no migration.
///
/// Deliberately thin next to `SleepNightRecord`: only what's needed to know
/// a sleep happened, when, how long, and how much of it was asleep. The
/// full physiology extraction (`FeatureExtractor`) stays scoped to the one
/// main-sleep session per night; running it a second time per nap is a
/// separate, larger cost/benefit call this pass doesn't make.
@Model
final class SleepEpisodeRecord {

    /// `"<nightKey>@<startDate-epoch-seconds>"` -- unique per episode, and
    /// stable across re-syncs of the same HealthKit session (start time
    /// doesn't move under re-processing the way derived fields do).
    @Attribute(.unique) var id: String

    /// The wake-date session group this episode belongs to -- the same key
    /// `SleepNightRecord.nightKey` uses for that group's main sleep, so the
    /// two can be joined without a second date-boundary calculation.
    var nightKey: String

    var startDate: Date
    var endDate: Date
    var timezoneIdentifier: String

    var episodeTypeRaw: String
    var episodeType: SleepEpisodeType {
        get { SleepEpisodeType(rawValue: episodeTypeRaw) ?? .unknown }
        set { episodeTypeRaw = newValue.rawValue }
    }

    var asleepMinutes: Double
    var timeInBedMinutes: Double
    var sourceName: String?

    var createdAt: Date

    init(
        id: String,
        nightKey: String,
        startDate: Date,
        endDate: Date,
        timezoneIdentifier: String,
        episodeType: SleepEpisodeType,
        asleepMinutes: Double,
        timeInBedMinutes: Double,
        sourceName: String?
    ) {
        self.id = id
        self.nightKey = nightKey
        self.startDate = startDate
        self.endDate = endDate
        self.timezoneIdentifier = timezoneIdentifier
        self.episodeTypeRaw = episodeType.rawValue
        self.asleepMinutes = asleepMinutes
        self.timeInBedMinutes = timeInBedMinutes
        self.sourceName = sourceName
        self.createdAt = .now
    }
}

/// What kind of sleep session an episode is, relative to that day's main
/// sleep. Classification here is a first pass -- clock-time heuristics, not
/// the fuller duration/schedule/shift-work-aware model a mature version
/// would use -- deliberately conservative so it doesn't mislabel edge cases
/// with false confidence.
enum SleepEpisodeType: String, Codable, Sendable {
    case nap
    case secondarySleep
    case unknown

    var displayName: String {
        switch self {
        case .nap: "Nap"
        case .secondarySleep: "Secondary sleep"
        case .unknown: "Sleep"
        }
    }
}
