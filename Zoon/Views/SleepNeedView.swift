import SwiftUI
import Charts

/// Tonight's estimated requirement, broken down into what it's built from.
struct SleepNeedView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    /// Set only when pushed from `CoreIntelligenceGrid`'s tile, so the push
    /// animation zooms outward from the tile instead of the generic
    /// slide-in -- `nil` for other entry points (e.g. the Insights hub row).
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    private var need: SleepNeed? { coordinator.state.context?.sleepNeed }
    /// Tonight's plan: the shortfall through last night, today's strain and
    /// today's naps.
    private var tonight: TonightPlan? { coordinator.state.context?.tonight }

    private func tonightTarget(_ need: SleepNeed) -> Double {
        tonight?.suggestedSleepTargetMinutes ?? need.totalNeedMinutes
    }
    private var learned: LearnedSleepNeed? { coordinator.state.context?.learnedSleepNeed }

    var body: some View {
        // `.zoom(...)` and `.automatic` are different concrete types
        // conforming to `NavigationTransition`, so branching the transition
        // value itself (e.g. via a ternary) doesn't type-check -- branching
        // the view instead lets each branch's `.navigationTransition(_:)`
        // call resolve its own concrete opaque type independently.
        if let zoomNamespace, let zoomID {
            content.navigationTransition(.zoom(sourceID: zoomID, in: zoomNamespace))
        } else {
            content.navigationTransition(.automatic)
        }
    }

    private var content: some View {
        ScrollView {
            CascadeStack(spacing: Theme.stackSpacing) {
                if let need {
                    hero(need)
                    ageCard
                    breakdownCard(need)
                    trendChart
                    explanationCard
                } else {
                    GatheringNights(
                        title: "No night yet",
                        message: "Your sleep baseline is learned from unconstrained nights you have actually slept.",
                        nights: 0,
                        needed: 1
                    )
                        .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Sleep Need")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Two figures, because they answer two questions.
    ///
    /// The baseline is where this person's unconstrained nights sit — it
    /// barely moves, and it is the closest thing here to an observation.
    /// Tonight's target is that baseline plus today's adjustments, and it is
    /// a planning suggestion. Showing only the composed total, as this did,
    /// let a figure carrying a debt repayment and a strain bonus read as a
    /// measured requirement. See `SleepNeed`.
    private func hero(_ need: SleepNeed) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Your baseline")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.inkSecondary)
                // A range where the nights support one, a single figure where
                // they do not — never a fabricated ±20 minutes.
                Text(baselineReading)
                    .font(Theme.numeral(30))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }

            VStack(spacing: 4) {
                Text("Tonight's suggested target")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.inkSecondary)
                // Tonight's plan's own target -- the one Tonight, the Coach
                // and the plan card use. `need.totalNeedMinutes` is last
                // night's, built from the debt carried *into* it; after a
                // 3-hour night the two were half an hour apart under the
                // same label.
                Text(SleepNightFeatures.formatMinutes(tonightTarget(need)))
                    .font(Theme.numeral(46))
                    .monospacedDigit()
                if tonight != nil, abs(need.totalNeedMinutes - tonightTarget(need)) >= 1 {
                    Text("Last night's target was \(SleepNightFeatures.formatMinutes(need.totalNeedMinutes))")
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            StatusPill(text: learned?.confidence.label ?? "Low confidence", tint: Theme.Metric.sleep)

            Text(provenanceLine)
                .font(Theme.text(10))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    /// The baseline as a band when the qualifying nights support one, and as
    /// a single figure when they do not.
    private var baselineReading: String {
        guard let learned else { return "—" }
        if learned.showsRange,
           let low = learned.typicalLowMinutes,
           let high = learned.typicalHighMinutes,
           high - low >= 5 {
            return "\(SleepNightFeatures.formatMinutes(low))–\(SleepNightFeatures.formatMinutes(high))"
        }
        return SleepNightFeatures.formatMinutes(learned.learnedMinutes ?? learned.minutes)
    }

    /// Where the baseline came from, said plainly, including when it is still
    /// mostly the goal the person set.
    private var provenanceLine: String {
        guard let learned else {
            return "Your baseline is learned from nights you have actually slept."
        }
        guard learned.learnedMinutes != nil else {
            return "Still your stated goal. Zoon needs \(LearnedSleepNeed.minimumQualifyingNights) qualifying nights before it starts learning a baseline of your own, and has \(learned.qualifyingNightCount)."
        }
        let basis = "Learned from \(learned.qualifyingNightCount) qualifying nights"
        return learned.showsRange
            ? "\(basis) — the range is where the middle of those nights sat, not a margin of error. Tonight's target adds today's adjustments below."
            : "\(basis), still blended with your stated goal. Tonight's target adds today's adjustments below."
    }

    /// The expert recommendation for the person's age, drawn on the same
    /// hours scale as their own baseline, so "is my need normal?" has an
    /// answer on the screen that shows the need.
    private var age: Int? { coordinator.demographic?.ageYears }

    @ViewBuilder
    private var ageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "For your age", systemImage: "person.crop.circle")
            if let age, let guideline = SleepNeedGuideline.forAge(age) {
                let baseline = learned?.learnedMinutes ?? learned?.minutes ?? preferences.sleepGoalMinutes
                HStack(alignment: .firstTextBaseline) {
                    Text("Recommended at \(age)")
                        .font(Theme.label(14, weight: .semibold))
                    Spacer()
                    Text(guideline.recommendedText)
                        .font(Theme.label(16, weight: .bold))
                        .foregroundStyle(Theme.Metric.sleep)
                }
                PopulationRangeBar(
                    scale: 300...660,
                    band: guideline.recommendedMinutes,
                    value: baseline,
                    tint: Theme.Metric.sleep
                )
                HStack {
                    Text("5h")
                    Spacer()
                    Text("8h")
                    Spacer()
                    Text("11h")
                }
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
                Text(ageSentence(guideline: guideline, baseline: baseline))
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if learned?.isOutsideAgeRange == true {
                    Text("Your nights point outside what is usual at your age, so Zoon leans toward your goal until more nights agree.")
                        .font(Theme.text(14))
                        .foregroundStyle(Theme.Family.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("National Sleep Foundation recommendation. The dot is your baseline.")
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
            } else {
                Text("Add your age in Settings, under You, to see how much sleep experts recommend at your age.")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func ageSentence(guideline: SleepNeedGuideline, baseline: Double) -> String {
        let yours = SleepNightFeatures.formatMinutes(baseline)
        switch guideline.fit(baseline) {
        case .withinRecommended:
            return "Your baseline of \(yours) sits inside the range for \(guideline.groupName)."
        case .belowRecommended, .wellBelow:
            return "Your baseline of \(yours) is under the range for \(guideline.groupName). If you often feel sleepy in the day, you may need more than you have been getting."
        case .aboveRecommended, .wellAbove:
            return "Your baseline of \(yours) is over the range for \(guideline.groupName). Some people simply need more; if you still wake unrefreshed, it is worth mentioning to a doctor."
        }
    }

    /// Tonight's drivers when there is a plan, so the rows explain the
    /// target above them. The total is shown as its own figure rather than
    /// summed: Autopilot holds the target to what one night's bedtime shift
    /// allows, so the rows can differ from it.
    private func breakdownCard(_ need: SleepNeed) -> some View {
        let rows: [(label: String, minutes: Double)] = tonight.map { plan in
            plan.drivers.map { (label: $0.label, minutes: $0.minutes) }
        } ?? need.contributions.map { (label: $0.label, minutes: $0.minutes) }
        let total = tonightTarget(need)
        let rowSum = rows.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What it's built from", systemImage: "list.bullet.rectangle")
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.label)
                        .font(Theme.label(12))
                    Spacer()
                    // The first row is the baseline itself, not an addition.
                    Text((index == 0 ? "" : row.minutes >= 0 ? "+" : "−") + SleepNightFeatures.formatMinutes(abs(row.minutes)))
                        .font(Theme.label(13, weight: .semibold))
                        .monospacedDigit()
                }
            }
            Divider().overlay(Theme.cardStroke)
            HStack {
                Text(tonight == nil ? "Total estimated need" : "Tonight's target")
                    .font(Theme.label(12, weight: .bold))
                Spacer()
                Text(SleepNightFeatures.formatMinutes(total))
                    .font(Theme.label(13, weight: .bold))
                    .monospacedDigit()
            }
            if abs(rowSum - total) >= 5 {
                Text("Tonight's plan moves bedtime by a bounded amount each night, so its target can differ from the sum above.")
                    .font(Theme.text(10))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    @State private var selectedDate: Date?

    @ViewBuilder
    private var trendChart: some View {
        let nights = Array(coordinator.recentNights.suffix(30))
        if nights.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Actual sleep vs. learned need", systemImage: "chart.bar")
                Chart {
                    ForEach(nights) { night in
                        BarMark(
                            x: .value("Date", night.date, unit: .day),
                            y: .value("Hours", night.total24hAsleepMinutes / 60)
                        )
                        .foregroundStyle(Theme.Metric.sleep.opacity(0.85))
                        .cornerRadius(2)
                    }

                    // The screen is titled and explained entirely in terms of
                    // the learned/blended need baseline (see `hero` and
                    // `learnedExplanationText`) -- the chart previously showed
                    // bars with no reference line at all despite being titled
                    // "vs. goal", so there was nothing on screen to actually
                    // compare a night against. `learned.minutes` is always
                    // populated (it falls back to the Settings goal itself
                    // below `minimumQualifyingNights`), so this line is never
                    // absent, and it tracks whichever baseline the rest of
                    // the screen is already describing.
                    if let learnedMinutes = learned?.minutes {
                        RuleMark(y: .value("Need", learnedMinutes / 60))
                            .foregroundStyle(Theme.Metric.sleep)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }

                    if let selectedDate, let night = nights.nearest(toDay: selectedDate) {
                        RuleMark(x: .value("Selected", night.date, unit: .day))
                            .foregroundStyle(Theme.neutral(0.25))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionBadge(
                                    title: night.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                    lines: [("Asleep", night.formattedTimeAsleep, Theme.Metric.sleep)]
                                )
                            }
                    }
                }
                .frame(height: 100)
                .chartXSelection(value: $selectedDate)
                // The reference line is the whole point of this chart, so
                // the summary has to carry it: bars alone would tell a
                // screen reader how long the nights were without saying
                // what they are being compared against.
                .chartSummary(
                    "Nightly sleep against your learned need, last \(nights.count) nights",
                    {
                        let hours = nights.map { $0.total24hAsleepMinutes / 60 }
                        let need = learned.map { "Need is \(SleepNightFeatures.formatMinutes($0.minutes)). " } ?? ""
                        let last = nights.last.map {
                            "Last night \($0.formattedTimeAsleep). "
                        } ?? ""
                        return need + last + ChartTrend.describe(hours) + "."
                    }()
                )
            }
            .glassCard()
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How this is estimated", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(learnedExplanationText)
                .font(Theme.text(10))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var learnedExplanationText: String {
        let base: String
        if let learned, learned.learnedMinutes != nil {
            base = """
                The baseline starts from your own recent history rather than just your goal: \
                the typical duration of your efficient, unfragmented, well-measured nights \
                (\(learned.qualifyingNightCount) of them so far), blended with your Settings \
                goal -- more weight on your own history the more qualifying nights you have, \
                up to \(LearnedSleepNeed.fullConfidenceNights).
                """
        } else {
            base = """
                Starts from your sleep goal in Settings. Once you have \
                \(LearnedSleepNeed.minimumQualifyingNights) or more nights of efficient, \
                well-measured sleep, this baseline starts blending in a figure learned from \
                your own history instead of relying on the goal alone.
                """
        }
        return base + """
             Tonight's target then adds a slice of the shortfall through last night and \
            today's exertion, and takes off today's naps -- so a harder day or a short night \
            genuinely raises it instead of treating every night the same. The shortfall itself \
            is tracked separately, each night against the need Zoon had learned by then -- see \
            Sleep Debt for how that number is built.
            """
    }
}

#Preview("Sleep Need") {
    NavigationStack { SleepNeedView() }
        .zoonPreviewEnvironment()
}
