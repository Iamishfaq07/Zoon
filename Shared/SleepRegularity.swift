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
    static func compute(nights: [SleepNightFeatures], calendar: Calendar = .current) -> SleepRegularity {
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

        let (weekday, weekend) = midpoints(nights: sorted, calendar: calendar)

        return SleepRegularity(
            index: index,
            nightCount: sorted.count,
            weekdayMidpoint: weekday,
            weekendMidpoint: weekend
        )
    }

    /// Median sleep midpoint for work days and free days.
    ///
    /// Free days are Saturday and Sunday mornings, which is a simplification —
    /// shift workers and anyone on a four-day week will be mislabelled. It's the
    /// same simplification the published social-jetlag questionnaire makes, and
    /// the alternative is asking the user to configure a work schedule, which
    /// almost nobody will do.
    private static func midpoints(
        nights: [SleepNightFeatures],
        calendar: Calendar
    ) -> (weekday: Double?, weekend: Double?) {

        var work: [Double] = []
        var free: [Double] = []

        for night in nights {
            let midpoint = night.bedtime.addingTimeInterval(
                night.wakeTime.timeIntervalSince(night.bedtime) / 2
            )
            let components = calendar.dateComponents([.hour, .minute], from: midpoint)
            var hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
            // Shift so an evening midpoint reads as negative and the median
            // isn't torn apart by the midnight wrap.
            if hour >= 18 { hour -= 24 }

            if calendar.isDateInWeekend(night.date) {
                free.append(hour)
            } else {
                work.append(hour)
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
            return "Your sleep timing is remarkably consistent. Across the research, regularity predicts long-term health outcomes more strongly than duration does — this is the harder win and you already have it."
        case .consistent:
            return "Your schedule holds together well. Tightening the remaining drift is worth more than chasing an extra twenty minutes in bed."
        case .variable:
            return "Your sleep timing moves around noticeably. Anchoring your wake time — even on free days — is the single most effective change available to you."
        case .erratic:
            return "Your sleep timing varies enough that your body clock never fully settles. Pick one wake time and hold it for two weeks; everything else gets easier afterwards."
        }
    }

    var socialJetlagDetail: String? {
        guard let jetlag = socialJetlagHours, jetlag >= 0.5 else { return nil }
        return String(
            format: "Your body clock shifts about %.1fh between work days and free days — physiologically similar to flying %@ timezones every weekend and back again.",
            jetlag,
            jetlag >= 1.5 ? "two" : "one"
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
