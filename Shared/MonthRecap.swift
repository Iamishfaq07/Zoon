import Foundation

/// One calendar month of sleep, summed up for sharing.
///
/// Built only from nights already stored: how many were recorded, the
/// average asleep, how many reached the goal and the longest run of them,
/// the usual bedtime and how much it wandered, the share of deep sleep, the
/// best night, and the change from the month before. Every figure is a
/// plain description of those nights. Nothing is predicted or scored.
struct MonthRecap: Hashable, Sendable {

    /// The month, first instant to the first instant of the next.
    let month: DateInterval
    let nightCount: Int
    let averageAsleepMinutes: Double
    let goalMinutes: Double
    /// Nights whose asleep total (naps included) reached the goal.
    let goalNights: Int
    /// The most consecutive calendar days that each reached the goal.
    let longestGoalStreak: Int
    /// Usual bedtime as minutes after midnight, 0..<1440. `nil` below
    /// `minimumNights`, where "usual" means nothing.
    let typicalBedtimeMinutes: Double?
    /// How far a typical bedtime strayed from that, minutes (median absolute
    /// deviation).
    let bedtimeSpreadMinutes: Double?
    /// Deep sleep as a share of asleep time, over staged nights only.
    let averageDeepPercent: Double?
    let bestNight: SleepNightFeatures?
    /// Average asleep against the previous month's, minutes. `nil` when the
    /// previous month has fewer than `minimumNights`.
    let changeFromPreviousMinutes: Double?
    /// Every day of the month with the asleep total when there was a night.
    let days: [Day]

    struct Day: Hashable, Sendable, Identifiable {
        let date: Date
        let asleepMinutes: Double?
        var id: Date { date }
    }

    /// Fewer nights than this and there is no month to describe.
    static let minimumNights = 5

    /// The calendar month containing `date`.
    static func calendarMonth(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: .month, for: date)
    }

    static func make(
        nights: [SleepNightFeatures],
        goalMinutes: Double,
        month: DateInterval,
        previousMonth: DateInterval? = nil,
        calendar: Calendar = .current
    ) -> MonthRecap? {
        let inMonth = nights
            .filter { month.start <= $0.date && $0.date < month.end }
            .sorted { $0.date < $1.date }
        guard inMonth.count >= minimumNights else { return nil }

        let asleep = inMonth.map(\.total24hAsleepMinutes)
        let average = asleep.reduce(0, +) / Double(asleep.count)
        let reached = inMonth.filter { $0.total24hAsleepMinutes >= goalMinutes }

        // Longest run of consecutive days that each reached the goal. A day
        // with no night breaks the run: an unrecorded night is not a met one.
        var longest = 0
        var run = 0
        var previousDay: Date?
        for night in inMonth {
            let day = calendar.startOfDay(for: night.date)
            let met = night.total24hAsleepMinutes >= goalMinutes
            if met {
                if let previousDay, calendar.dateComponents([.day], from: previousDay, to: day).day == 1, run > 0 {
                    run += 1
                } else {
                    run = 1
                }
            } else {
                run = 0
            }
            longest = max(longest, run)
            previousDay = day
        }

        // Bedtimes folded at noon, so 23:30 and 00:30 sit an hour apart
        // rather than a day.
        let bedtimes = inMonth.map { night -> Double in
            var local = calendar
            local.timeZone = night.timeZone
            let parts = local.dateComponents([.hour, .minute], from: night.bedtime)
            let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            return minutes < 12 * 60 ? minutes + 24 * 60 : minutes
        }
        let medianBedtime = Statistics.median(bedtimes)
        let spread = Statistics.medianAbsoluteDeviation(bedtimes)

        let staged = inMonth.filter { $0.hasStageBreakdown && $0.timeAsleepMinutes > 0 }
        let deepPercent: Double? = staged.isEmpty ? nil
            : staged.map { $0.deepMinutes / $0.timeAsleepMinutes * 100 }.reduce(0, +) / Double(staged.count)

        // The longest night among the efficient ones; the longest overall
        // when none was efficient.
        let efficient = inMonth.filter { $0.sleepEfficiencyPercent >= 85 }
        let best = (efficient.isEmpty ? inMonth : efficient).max { $0.timeAsleepMinutes < $1.timeAsleepMinutes }

        var change: Double?
        if let previousMonth {
            let before = nights.filter { previousMonth.start <= $0.date && $0.date < previousMonth.end }
            if before.count >= minimumNights {
                change = average - before.map(\.total24hAsleepMinutes).reduce(0, +) / Double(before.count)
            }
        }

        var days: [Day] = []
        var cursor = calendar.startOfDay(for: month.start)
        while cursor < month.end {
            let night = inMonth.first { calendar.isDate($0.date, inSameDayAs: cursor) }
            days.append(Day(date: cursor, asleepMinutes: night?.total24hAsleepMinutes))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return MonthRecap(
            month: month,
            nightCount: inMonth.count,
            averageAsleepMinutes: average,
            goalMinutes: goalMinutes,
            goalNights: reached.count,
            longestGoalStreak: longest,
            typicalBedtimeMinutes: medianBedtime.map { $0.truncatingRemainder(dividingBy: 24 * 60) },
            bedtimeSpreadMinutes: spread,
            averageDeepPercent: deepPercent,
            bestNight: best,
            changeFromPreviousMinutes: change,
            days: days
        )
    }

    /// One sentence for the top of the recap.
    var headline: String {
        let share = Double(goalNights) / Double(max(nightCount, 1))
        if share >= 0.7 {
            return "\(goalNights) of \(nightCount) nights reached your goal."
        }
        if let change = changeFromPreviousMinutes, abs(change) >= 15 {
            let amount = SleepNightFeatures.formatMinutes(abs(change))
            return change > 0
                ? "You slept \(amount) more a night than the month before."
                : "You slept \(amount) less a night than the month before."
        }
        return "About \(SleepNightFeatures.formatMinutes(averageAsleepMinutes)) a night, most nights."
    }
}
