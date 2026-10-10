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
            return "Learned from nights you sleep."
        }
        guard learned.learnedMinutes != nil else {
            return "Your goal for now. \(learned.qualifyingNightCount) of \(LearnedSleepNeed.minimumQualifyingNights) nights toward your own."
        }
        let basis = "From \(learned.qualifyingNightCount) of your nights"
        return learned.showsRange
            ? "\(basis). The range is where most of them sat."
            : "\(basis), blended with your goal."
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
                    Text("Unusual for your age, so Zoon leans on your goal until more nights agree.")
                        .font(Theme.text(14))
                        .foregroundStyle(Theme.Family.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("National Sleep Foundation range. The dot is you.")
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
            } else {
                Text("Add your age in Settings › You to compare.")
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
            return "\(yours) is inside the range for \(guideline.groupName)."
        case .belowRecommended, .wellBelow:
            return "\(yours) is under the range for \(guideline.groupName). Sleepy by day? You may need more."
        case .aboveRecommended, .wellAbove:
            return "\(yours) is over the range for \(guideline.groupName). If you still wake unrefreshed, mention it to a doctor."
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
            NeedStackBar(minutes: rows.map(\.minutes), colors: rows.indices.map(Self.segmentColor))
                .frame(height: 14)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Circle()
                        .fill(row.minutes >= 0 ? Self.segmentColor(index) : Theme.neutral(0.25))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
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
                Text("Tonight's plan moves bedtime a little at a time, so it can differ from this.")
                    .font(Theme.text(10))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    /// The baseline in the sleep colour, each addition in a lighter or
    /// warmer step after it.
    private static func segmentColor(_ index: Int) -> Color {
        let palette: [Color] = [
            Theme.Family.sleep, Theme.Family.bodySignals, Theme.Family.circadian,
            Theme.Family.breathing, Theme.Family.recovery
        ]
        return palette[index % palette.count]
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
        ExplainDisclosure(title: "How this is worked out", lines: explanationLines, systemImage: "info.circle")
    }

    private var explanationLines: [String] {
        var lines: [String]
        if let learned, learned.learnedMinutes != nil {
            lines = [
                "Baseline: your usual length on clean, well-measured nights (\(learned.qualifyingNightCount) so far), blended with your goal.",
                "The more nights, the more weight on yours, up to \(LearnedSleepNeed.fullConfidenceNights)."
            ]
        } else {
            lines = [
                "Baseline: your goal in Settings for now.",
                "After \(LearnedSleepNeed.minimumQualifyingNights) clean nights, Zoon blends in what it learns from you."
            ]
        }
        lines.append("Tonight's target adds part of your sleep debt and today's effort, and takes off naps.")
        lines.append("Sleep debt is counted on its own, under Owed.")
        return lines
    }
}

/// The target as one bar: the baseline, then each addition after it, so
/// the eye sees how much of tonight is the usual night and how much is
/// today. Reductions (naps) are left out of the bar; their rows say so.
private struct NeedStackBar: View {
    let minutes: [Double]
    let colors: [Color]
    @State private var progress: Double = 0

    var body: some View {
        let positive = minutes.map { max(0, $0) }
        let total = max(1, positive.reduce(0, +))
        GeometryReader { proxy in
            let usable = proxy.size.width - CGFloat(max(0, positive.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(positive.enumerated()), id: \.offset) { index, value in
                    if value > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colors[index])
                            .frame(width: max(3, usable * CGFloat(value / total) * progress))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .drawOnce(id: minutes, progress: $progress)
        .accessibilityHidden(true)
    }
}

#Preview("Sleep Need") {
    NavigationStack { SleepNeedView() }
        .zoonPreviewEnvironment()
}
