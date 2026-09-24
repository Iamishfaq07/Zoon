import Foundation

/// How logged mood compares after nights that met sleep need and after
/// nights that fell well short of it.
///
/// Mood comes from Apple Health's State of Mind (iOS 18): the daily mood a
/// person logs in the Health app or the Mindfulness app on Apple Watch,
/// a valence from -1 (very unpleasant) to 1 (very pleasant). Zoon only reads
/// it, and only with Lifestyle Insights on.
///
/// This is an association across the person's own days, never a cause: a bad
/// day can shorten a night as easily as a short night can spoil a day, and
/// the wording says so. Nothing is shown until each side has enough days.
enum MoodSleepLink {

    /// One day's mood: the mean valence of the daily-mood logs dated that day.
    struct DailyMood: Equatable, Sendable {
        /// Start of the local day.
        let day: Date
        /// -1...1.
        let valence: Double
    }

    /// Days needed on each side before anything is said.
    static let minimumDaysPerGroup = 5
    /// A night at least this close to its need counts as having met it.
    static let metNeedToleranceMinutes: Double = 15
    /// A night at least this far below its need counts as short.
    static let shortByMinutes: Double = 60
    /// Smallest valence difference worth describing as a difference (the
    /// scale runs -1 to 1).
    static let meaningfulDifference = 0.15

    struct Result: Equatable, Sendable {
        let daysAfterFullNights: Int
        let daysAfterShortNights: Int
        /// `nil` until both groups have `minimumDaysPerGroup` days.
        let moodAfterFull: Double?
        let moodAfterShort: Double?

        var isReady: Bool { moodAfterFull != nil && moodAfterShort != nil }

        var difference: Double? {
            guard let full = moodAfterFull, let short = moodAfterShort else { return nil }
            return full - short
        }

        /// The one sentence the card shows.
        var sentence: String {
            guard let difference else {
                let needFull = max(0, MoodSleepLink.minimumDaysPerGroup - daysAfterFullNights)
                let needShort = max(0, MoodSleepLink.minimumDaysPerGroup - daysAfterShortNights)
                return "Zoon compares mood you log in Apple Health after full nights and after short ones. "
                    + "It needs \(needFull) more after a full night and \(needShort) more after a short one."
            }
            let counts = "(\(daysAfterFullNights) days after full nights, \(daysAfterShortNights) after short ones)"
            if difference >= MoodSleepLink.meaningfulDifference {
                return "Your logged mood tended to be more pleasant after nights that met your sleep need than after nights an hour or more short \(counts). This is a pattern in your own days; it does not show which came first."
            }
            if difference <= -MoodSleepLink.meaningfulDifference {
                return "Your logged mood tended to be less pleasant after nights that met your sleep need than after short ones \(counts). That is unusual, and may reflect what else was happening on those days."
            }
            return "Your logged mood was about the same after full nights and short ones \(counts)."
        }
    }

    /// Pairs each mood day with the night that ended that morning.
    static func compute(
        moods: [DailyMood],
        nights: [SleepNightFeatures],
        calendar: Calendar = .current
    ) -> Result {
        var nightByDay: [Date: SleepNightFeatures] = [:]
        for night in nights {
            nightByDay[calendar.startOfDay(for: night.date)] = night
        }
        var full: [Double] = []
        var short: [Double] = []
        for mood in moods where mood.valence.isFinite {
            guard let night = nightByDay[calendar.startOfDay(for: mood.day)],
                  let need = night.sleepNeedBaselineMinutes, need > 0 else { continue }
            let gap = need - night.timeAsleepMinutes
            if gap <= metNeedToleranceMinutes {
                full.append(min(1, max(-1, mood.valence)))
            } else if gap >= shortByMinutes {
                short.append(min(1, max(-1, mood.valence)))
            }
        }
        let ready = full.count >= minimumDaysPerGroup && short.count >= minimumDaysPerGroup
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
        return Result(
            daysAfterFullNights: full.count,
            daysAfterShortNights: short.count,
            moodAfterFull: ready ? mean(full) : nil,
            moodAfterShort: ready ? mean(short) : nil
        )
    }

    /// Averages several logs on one day into one value per day.
    static func dailyMeans(_ samples: [(date: Date, valence: Double)], calendar: Calendar = .current) -> [DailyMood] {
        let grouped = Dictionary(grouping: samples.filter { $0.valence.isFinite }) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { day, logs in DailyMood(day: day, valence: logs.map(\.valence).reduce(0, +) / Double(logs.count)) }
            .sorted { $0.day < $1.day }
    }
}
