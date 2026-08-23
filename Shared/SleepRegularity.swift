import Foundation

/// How consistent your sleep timing is, and what it costs you.
///
/// This is **Sleep Timing Regularity**, built on the same core idea as the
/// academic Sleep Regularity Index -- the probability that you're in the same
/// state (asleep or awake) at two moments 24 hours apart, rescaled to 0–100 --
/// but it is not a full implementation of that metric and should not be
/// presented as one. The genuine SRI samples every moment of a full 24-hour
/// day, including daytime awake-to-awake agreement; this only samples a
/// window around each night's actual sleep period (`compute`'s
/// `windowStart`/`windowEnd`, roughly bedtime−2h to wake+2h), so two people
/// with identical sleep timing but very different daytime schedules can score
/// differently here even though a full SRI would treat them the same.
/// Deliberately not labelled "SRI" anywhere user-facing for that reason --
/// see `RegularityCard`.
///
/// The metric it approximates still earns its place: across several large
/// cohort studies, regularity of this kind predicts mortality risk *more
/// strongly than sleep duration does*, and it's almost absent from consumer
/// apps. Duration is the number everyone optimises; timing consistency is the
/// one that moves the needle and nobody shows you.
///
/// Widening the sampled window to a genuine full calendar day was
/// considered and deliberately not done: without real daytime activity data
/// (Zoon has no accelerometer-based wake/movement signal, only known sleep
/// intervals), every extra daytime hour would just be scored "awake" for
/// both nights being compared, and most people are awake most of the day
/// every day -- so it would inflate and flatten every score toward the top
/// of the range rather than add real information, diluting exactly the
/// night-to-night signal this metric exists to surface. That's a
/// correctness regression dressed up as a completeness improvement, not a
/// genuine one. The honest path (never presenting this as the real metric)
/// stays the fix.
///
/// The computation needs the actual asleep intervals, not just totals, which is
/// why this lives alongside `StageSegment` rather than in the score file.
struct SleepRegularity: Codable, Hashable, Sendable {

    /// 0–100. Higher is more regular.
    let index: Double
    /// Nights the index was computed across.
    let nightCount: Int

    /// Median sleep midpoint on work days, as hours from midnight
    /// (evening negative — 03:30 is 3.5, 23:30 is −0.5).
    let weekdayMidpoint: Double?
    /// Median sleep midpoint on free days.
    let weekendMidpoint: Double?

    /// Social jetlag: how far your body clock shifts between work days and free
    /// days, in hours. The name is literal — a two-hour weekend shift is
    /// physiologically similar to flying two timezones every Friday and back
    /// every Monday.
    var socialJetlagHours: Double? {
        guard let weekday = weekdayMidpoint, let weekend = weekendMidpoint else { return nil }
        return abs(weekend - weekday)
    }

    /// Nights required before an index is reported. SRI compares each night to
    /// the next, so n nights yield n−1 comparisons; below a week it's noise.
    static let minimumNights = 7

    // MARK: - Computation

    /// Computes SRI from consecutive nights.
    ///
    /// Implementation note: rather than sampling every minute of a 24-hour day
    /// across the whole record (the textbook formulation, and enormously
    /// wasteful here), this compares consecutive night pairs on a 5-minute grid
    /// spanning each pair's union. Same quantity, small fraction of the work,
    /// and the resolution is far finer than the underlying data justifies
    /// anyway — HealthKit stage samples are rarely shorter than a few minutes.
    /// Default `Calendar.component(.weekday:)` values (1 = Sunday ... 7 =
    /// Saturday) counted as obligation days -- the standard Mon-Fri workweek.
    /// `UserPreferences.obligationWeekdays` overrides this when a caller has
    /// access to it (this file is `Shared`, compiled into the Watch and
    /// widget targets too, so it can't depend on that app-only type); every
    /// existing caller that doesn't pass one keeps today's calendar-weekend
    /// behavior exactly.
    static let defaultObligationWeekdays: Set<Int> = [2, 3, 4, 5, 6]

    /// - Parameter obligationWeekdays: see `defaultObligationWeekdays`.
    static func compute(
        nights: [SleepNightFeatures],
        obligationWeekdays: Set<Int> = defaultObligationWeekdays,
        calendar: Calendar = .current
    ) -> SleepRegularity {
        let sorted = nights.sorted { $0.bedtime < $1.bedtime }

        guard sorted.count >= minimumNights else {
            return SleepRegularity(
                index: 0, nightCount: sorted.count,
                weekdayMidpoint: nil, weekendMidpoint: nil
            )
        }

        let step: TimeInterval = 300  // 5 minutes
        let day: TimeInterval = 86_400

        var agreements = 0
        var comparisons = 0

        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            // Only compare nights that are actually a day apart. A gap in the
            // record (watch off for a week) must not be scored as irregularity —
            // that would punish people for missing data rather than for erratic
            // sleep.
            let gap = next.bedtime.timeIntervalSince(previous.bedtime)
            guard gap > day * 0.5, gap < day * 1.5 else { continue }

            // Walk the window covered by the earlier night, asking at each step
            // whether the state 24h later matches.
            let windowStart = previous.bedtime.addingTimeInterval(-2 * 3600)
            let windowEnd = previous.wakeTime.addingTimeInterval(2 * 3600)

            var cursor = windowStart
            while cursor < windowEnd {
                let asleepNow = previous.isAsleep(at: cursor)
                // Calendar-day addition, not cursor + 86,400 seconds: on a DST
                // transition night that's a 23- or 25-hour day, "24 hours
                // later" by the clock is not 86,400 seconds later in absolute
                // time. Comparing against the wrong wall-clock instant would
                // read as a spurious agreement or disagreement for every
                // sample that night, right when DST nights are already the
                // one time a regularity metric most needs to stay correct.
                let sameTimeNextDay = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(day)
                let asleepTomorrow = next.isAsleep(at: sameTimeNextDay)
                if asleepNow == asleepTomorrow { agreements += 1 }
                comparisons += 1
                cursor = cursor.addingTimeInterval(step)
            }
        }

        // SRI = 2 × agreement% − 100, so chance agreement (50%) maps to 0
        // rather than to a flattering 50.
        let index: Double
        if comparisons > 0 {
            let agreement = Double(agreements) / Double(comparisons)
            index = max(0, min(100, 2 * agreement * 100 - 100))
        } else {
            index = 0
        }

        let (weekday, weekend) = midpoints(nights: sorted, obligationWeekdays: obligationWeekdays, calendar: calendar)

        return SleepRegularity(
            index: index,
            nightCount: sorted.count,
            weekdayMidpoint: weekday,
            weekendMidpoint: weekend
        )
    }

    /// Median sleep midpoint for work days and free days.
    ///
    /// Free days are whichever `obligationWeekdays` doesn't cover -- by
    /// default the calendar weekend, but configurable in Settings for
    /// anyone whose schedule doesn't match a standard Mon-Fri job (a
    /// four-day week, weekend retail shifts, and so on). This used to be a
    /// hardcoded Saturday/Sunday check with no way to correct it.
    ///
    /// Each night's wall-clock hour and weekday are read using *that night's
    /// own* timezone (`night.timeZoneIdentifier`), not the caller's `calendar`
    /// -- a night recorded in Tokyo doesn't change which local hour someone
    /// went to bed just because they've since flown to New York. `calendar`
    /// only supplies the locale behavior, its timeZone is overridden per
    /// night.
    private static func midpoints(
        nights: [SleepNightFeatures],
        obligationWeekdays: Set<Int>,
        calendar: Calendar
    ) -> (weekday: Double?, weekend: Double?) {

        var work: [Double] = []
        var free: [Double] = []
        var localCalendar = calendar

        for night in nights {
            localCalendar.timeZone = night.timeZone
            let midpoint = night.bedtime.addingTimeInterval(
                night.wakeTime.timeIntervalSince(night.bedtime) / 2
            )
            let components = localCalendar.dateComponents([.hour, .minute], from: midpoint)
            var hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
            // Shift so an evening midpoint reads as negative and the median
            // isn't torn apart by the midnight wrap.
            if hour >= 18 { hour -= 24 }

            let weekday = localCalendar.component(.weekday, from: night.date)
            if obligationWeekdays.contains(weekday) {
                work.append(hour)
            } else {
                free.append(hour)
            }
        }

        return (median(work), median(free))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}

// MARK: - Presentation

extension SleepRegularity {

    enum Band: String, Sendable {
        case erratic, variable, consistent, exemplary

        var label: String {
            switch self {
            case .erratic: "Erratic"
            case .variable: "Variable"
            case .consistent: "Consistent"
            case .exemplary: "Exemplary"
            }
        }
    }

    var band: Band {
        switch index {
        case ..<50: .erratic
        case 50..<70: .variable
        case 70..<85: .consistent
        default: .exemplary
        }
    }

    var hasEnoughData: Bool { nightCount >= Self.minimumNights }

    var detail: String {
        guard hasEnoughData else {
            return "Zoon needs about a week of nights before it can measure how regular your schedule is."
        }
        switch band {
        case .exemplary:
            return "Your sleep timing is remarkably consistent. Population studies have associated steady sleep timing like this with better long-term health outcomes — this is a harder habit to build than logging hours, and you already have it."
        case .consistent:
            return "Your schedule holds together well. Tightening the remaining drift is likely worth more than chasing an extra twenty minutes in bed."
        case .variable:
            return "Your sleep timing moves around noticeably. Anchoring your wake time — even on free days — tends to steady it more than adjusting bedtime alone."
        case .erratic:
            return "Your sleep timing varies enough that your body clock may not be settling into a steady rhythm. Picking one wake time and holding it for two weeks is a reasonable place to start."
        }
    }

    var socialJetlagDetail: String? {
        guard let jetlag = socialJetlagHours, jetlag >= 0.5 else { return nil }
        return String(
            format: "Your body clock shifts about %.1fh between work days and free days — a swing that size can feel a lot like crossing %@ time zone%@ every weekend, without the travel.",
            jetlag,
            jetlag >= 1.5 ? "two" : "one",
            jetlag >= 1.5 ? "s" : ""
        )
    }
}

// MARK: - Interval lookup

extension SleepNightFeatures {

    /// Whether the user was asleep at an instant.
    ///
    /// Uses the stage timeline when present — that's the truth. Falls back to
    /// the session bounds when a source gave no staging, which slightly
    /// overstates sleep (in-bed-but-awake counts) but keeps SRI computable for
    /// iPhone-only users rather than excluding them entirely.
    func isAsleep(at instant: Date) -> Bool {
        if !stageSegments.isEmpty {
            return stageSegments.contains { segment in
                SleepStage.asleepStages.contains(segment.stage)
                    && segment.start <= instant
                    && instant < segment.end
            }
        }
        return bedtime <= instant && instant < wakeTime
    }
}
