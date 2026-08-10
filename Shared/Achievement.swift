import Foundation

/// Badges, and the rules that unlock them.
///
/// ## The one design rule that matters
///
/// **Nothing here can ever be taken away.** Once earned, an achievement is
/// permanent, and no badge is defined in terms of an unbroken run that a single
/// bad night destroys.
///
/// That is not softness, it's the whole point. Streak mechanics work in a
/// language app because missing a day of Spanish costs you nothing but the
/// streak. In a sleep app they invert the product: a person lying awake at 1am
/// watching a 60-night streak die is being made *worse* at the thing the app
/// exists to help with. Sleep anxiety is a real and well-documented failure
/// mode of sleep tracking, and gamification is the fastest route to it.
///
/// So the counters here are cumulative ("40 nights at goal", in total, ever)
/// or best-ever ("your longest run was 12"), never live-or-die.
///
/// ## Progress is always visible
///
/// Every achievement reports `progress` in 0...1 even while locked, so the
/// grid reads as a map rather than a set of mysteries. A locked badge with no
/// hint is just a question mark, and question marks make people feel behind.
struct Achievement: Identifiable, Hashable, Sendable {

    enum Category: String, CaseIterable, Sendable {
        case duration, consistency, quality, recovery, habits

        var label: String {
            switch self {
            case .duration: "Duration"
            case .consistency: "Consistency"
            case .quality: "Quality"
            case .recovery: "Recovery"
            case .habits: "Habits"
            }
        }
    }

    /// Tiers exist to pace the grid, not to rank the user. A bronze badge is an
    /// earlier badge, not a worse one.
    enum Tier: Int, Comparable, Sendable {
        case bronze = 0, silver, gold

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .bronze: "Bronze"
            case .silver: "Silver"
            case .gold: "Gold"
            }
        }
    }

    let id: String
    let title: String
    /// What earns it. Written as a plain statement, present tense.
    let detail: String
    let symbol: String
    let category: Category
    let tier: Tier

    /// The measured value, and what it takes. Kept as numbers rather than a
    /// formatted string so the view can render a bar.
    let value: Double
    let target: Double

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, value / target))
    }

    var isUnlocked: Bool { value >= target }

    /// "7 / 30 nights" — the honest version of a locked badge.
    var progressText: String {
        let shown = min(value, target)
        return "\(Int(shown.rounded())) / \(Int(target.rounded()))"
    }
}

/// Evaluates every achievement from the record.
///
/// Pure: history in, badges out. No storage, no dates-of-unlock, no side
/// effects — which means the whole grid can be exercised from mock data, and a
/// badge can never be "stuck" unlocked by a stale cache disagreeing with the
/// data.
enum AchievementEngine {

    /// Everything Zoon can award.
    static func evaluate(
        nights: [SleepNightFeatures],
        goalMinutes: Double,
        journalTaggedNights: Int = 0,
        napCount: Int = 0,
        regularityIndex: Double? = nil
    ) -> [Achievement] {

        let sorted = nights.sorted { $0.date < $1.date }
        let atGoal = sorted.filter { $0.timeAsleepMinutes >= goalMinutes }

        var out: [Achievement] = []

        // MARK: Duration — cumulative nights at goal, never a live streak.
        for (tier, target) in [(Achievement.Tier.bronze, 7.0),
                               (.silver, 30.0),
                               (.gold, 100.0)] {
            out.append(Achievement(
                id: "goal-\(Int(target))",
                title: goalTitle(target),
                detail: "Hit your sleep goal on \(Int(target)) nights, in total.",
                symbol: "moon.zzz.fill",
                category: .duration,
                tier: tier,
                value: Double(atGoal.count),
                target: target
            ))
        }

        // MARK: Consistency — best run ever, which cannot be lost.
        let best = Double(longestRun(sorted, goalMinutes: goalMinutes))
        for (tier, target) in [(Achievement.Tier.bronze, 3.0),
                               (.silver, 7.0),
                               (.gold, 14.0)] {
            out.append(Achievement(
                id: "run-\(Int(target))",
                title: "\(Int(target)) in a row",
                // "Your best run" rather than "your current run": the number
                // only ever goes up, so the badge is a record, not a leash.
                detail: "Your best run of nights at goal reached \(Int(target)).",
                symbol: "flame.fill",
                category: .consistency,
                tier: tier,
                value: best,
                target: target
            ))
        }

        if let index = regularityIndex {
            out.append(Achievement(
                id: "regularity-80",
                title: "Clockwork",
                detail: "Reach a sleep regularity index of 80.",
                symbol: "clock.badge.checkmark.fill",
                category: .consistency,
                tier: .gold,
                value: index,
                target: 80
            ))
        }

        // MARK: Quality
        let deepNights = sorted.filter { ($0.deepPercentOfAsleep ?? 0) >= 20 }.count
        out.append(Achievement(
            id: "deep-20",
            title: "Deep diver",
            detail: "Spend 20% or more of a night in deep sleep, 20 times.",
            symbol: "waveform.path.ecg",
            category: .quality,
            tier: .silver,
            value: Double(deepNights),
            target: 20
        ))

        let remNights = sorted.filter { ($0.remPercentOfAsleep ?? 0) >= 25 }.count
        out.append(Achievement(
            id: "rem-20",
            title: "Dreamer",
            detail: "Spend 25% or more of a night in REM, 20 times.",
            symbol: "brain.head.profile",
            category: .quality,
            tier: .silver,
            value: Double(remNights),
            target: 20
        ))

        let efficientNights = sorted.filter { $0.sleepEfficiencyPercent >= 90 }.count
        out.append(Achievement(
            id: "efficiency-90",
            title: "Straight through",
            detail: "Record 90% sleep efficiency on 15 nights.",
            symbol: "bed.double.fill",
            category: .quality,
            tier: .bronze,
            value: Double(efficientNights),
            target: 15
        ))

        // MARK: Recovery
        let lowLatency = sorted.filter { ($0.sleepLatencyMinutes ?? 99) <= 10 }.count
        out.append(Achievement(
            id: "latency-10",
            title: "Out like a light",
            detail: "Fall asleep within 10 minutes, 25 times.",
            symbol: "powersleep",
            category: .recovery,
            tier: .silver,
            value: Double(lowLatency),
            target: 25
        ))

        // Debt cleared. Measured as nights where the rolling 14-day shortfall
        // sat under half an hour — "no debt" is a range, not a point.
        let clearNights = sorted.filter { abs($0.sleepDebtMinutes14Day ?? 999) <= 30 }.count
        out.append(Achievement(
            id: "debt-clear",
            title: "Paid off",
            detail: "Carry essentially no sleep debt on 10 nights.",
            symbol: "checkmark.seal.fill",
            category: .recovery,
            tier: .gold,
            value: Double(clearNights),
            target: 10
        ))

        // MARK: Habits — the ones the user drives directly.
        out.append(Achievement(
            id: "journal-14",
            title: "Note taker",
            detail: "Tag your behaviour on 14 nights. That's when correlations start working.",
            symbol: "square.and.pencil",
            category: .habits,
            tier: .bronze,
            value: Double(journalTaggedNights),
            target: 14
        ))

        out.append(Achievement(
            id: "nap-10",
            title: "Nap strategist",
            detail: "Log 10 naps.",
            symbol: "sun.horizon.fill",
            category: .habits,
            tier: .bronze,
            value: Double(napCount),
            target: 10
        ))

        out.append(Achievement(
            id: "history-90",
            title: "Long view",
            detail: "Build 90 nights of history. Every baseline in Zoon gets sharper with it.",
            symbol: "chart.xyaxis.line",
            category: .habits,
            tier: .gold,
            value: Double(sorted.count),
            target: 90
        ))

        return out
    }

    private static func goalTitle(_ target: Double) -> String {
        switch Int(target) {
        case 7: "First week"
        case 30: "A month of it"
        default: "Century"
        }
    }

    /// Longest consecutive run of nights at goal, over the whole record.
    ///
    /// Consecutive by *calendar day*, so a missing night breaks the run rather
    /// than silently bridging a gap — two nights either side of a week away
    /// are not "in a row".
    static func longestRun(
        _ nights: [SleepNightFeatures],
        goalMinutes: Double,
        calendar: Calendar = .current
    ) -> Int {
        var best = 0
        var current = 0
        var previous: Date?

        for night in nights {
            let metGoal = night.timeAsleepMinutes >= goalMinutes
            let isNextDay = previous.map {
                calendar.dateComponents([.day], from: $0, to: night.date).day == 1
            } ?? false

            current = (metGoal && isNextDay) ? current + 1 : (metGoal ? 1 : 0)
            best = max(best, current)
            previous = night.date
        }
        return best
    }

    /// The most recently earned badge, for the widget and the More tab.
    ///
    /// "Most recent" is approximated by the hardest unlocked one, since the
    /// engine is stateless and doesn't record unlock dates. That is the right
    /// trade: a stored date would be one more thing that can disagree with the
    /// data, and the badge worth showing is the impressive one anyway.
    static func headline(_ achievements: [Achievement]) -> Achievement? {
        achievements
            .filter(\.isUnlocked)
            .max { ($0.tier, $0.target) < ($1.tier, $1.target) }
    }

    /// Closest to unlocking, among those still locked. The useful other half of
    /// the summary: what's next.
    static func nextUp(_ achievements: [Achievement]) -> Achievement? {
        achievements
            .filter { !$0.isUnlocked && $0.progress > 0 }
            .max { $0.progress < $1.progress }
    }
}
