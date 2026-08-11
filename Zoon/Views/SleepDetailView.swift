import SwiftUI

/// The full night: shape, stages, need, timing, and vitals.
struct SleepDetailView: View {

    let context: DayContext

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                headline
                SleepNeedCard(need: context.sleepNeed)
                hypnogramCard
                stagesCard
                timingCard
                ChronotypeCard(chronotype: context.chronotype)
                dataCompletenessCard
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CoachChatView(night: context.night)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
        }
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text(context.night.formattedTimeAsleep)
                .font(Theme.numeral(52))
                .monospacedDigit()

            Text(context.night.date, format: .dateTime.weekday(.wide).month().day())
                .font(Theme.label(13))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                StatusPill(
                    text: "\(Int(context.sleepNeed.performancePercent))% of need",
                    tint: Theme.Metric.sleep
                )
                StatusPill(
                    text: "\(context.sleepScore.value) score",
                    tint: Theme.recoveryColor(Double(context.sleepScore.value))
                )
                if context.night.isMock {
                    StatusPill(text: "Sample", systemImage: "wand.and.stars", tint: .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var hypnogramCard: some View {
        if !context.night.stageSegments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Sleep Stages",
                    subtitle: "Deep sleep clusters early; REM builds toward morning.",
                    systemImage: "chart.xyaxis.line"
                )
                HypnogramView(segments: context.night.stageSegments)
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private var stagesCard: some View {
        if context.night.hasStageBreakdown {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Stage Breakdown", systemImage: "square.stack.3d.up")
                StageProportionBar(features: context.night)
                StageLegend(features: context.night)
            }
            .glassCard()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Stage Breakdown", systemImage: "applewatch.slash")
                Text("""
                    \(context.night.sourceName ?? "This source") records sleep without \
                    breaking it into stages. Wearing an Apple Watch to bed adds Deep, REM, and Core.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        }
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Timing & Quality", systemImage: "clock")

            row("Bedtime", context.night.bedtime.formatted(.dateTime.hour().minute()))
            row("Wake time", context.night.wakeTime.formatted(.dateTime.hour().minute()))
            row(
                context.night.timeInBedIsEstimated ? "Time in bed (estimated)" : "Time in bed",
                SleepNightFeatures.formatMinutes(context.night.timeInBedMinutes),
                definitionTitle: context.night.timeInBedIsEstimated ? "Estimated Time in Bed" : nil,
                definitionSymbol: "bed.double",
                definition: context.night.timeInBedIsEstimated ? [
                    "Your sleep source (most often an Apple Watch on its own) doesn't record when you got into or out of bed, so this is standing in with the span from your first sleep reading to your last -- it leaves out any time spent lying awake before falling asleep or after waking, so it tends to run a little short.",
                    "An iPhone sleep schedule or a third-party app that logs in-bed time directly would make this exact instead of estimated."
                ] : nil
            )
            row(
                "Efficiency", "\(Int(context.night.sleepEfficiencyPercent))%",
                definitionTitle: "Sleep Efficiency", definitionSymbol: "gauge.with.dots.needle.67percent",
                definition: [
                    "The percentage of your time in bed that you actually spent asleep -- total sleep time divided by time in bed.",
                    "Above 85% is generally considered efficient. A lower number usually means either a long time falling asleep or a lot of time awake overnight, both broken out separately below."
                ] + (context.night.timeInBedIsEstimated ? [
                    "Tonight's time-in-bed figure is estimated rather than measured (see the row above), so this efficiency number is likely a little higher than your true efficiency would read with exact in-bed data."
                ] : [])
            )
            if let latency = context.night.sleepLatencyMinutes {
                row(
                    "Fell asleep in", "\(Int(latency)) min",
                    definitionTitle: "Sleep Latency", definitionSymbol: "hourglass",
                    definition: [
                        "The time from getting into bed to your first sustained sleep. Only available when your sleep source records in-bed time -- Apple Watch alone doesn't, so this needs an iPhone sleep schedule or a third-party app contributing that data.",
                        "Under 20 minutes is typical for most people. A latency that's crept up over several nights is often more meaningful than one long night."
                    ]
                )
            }
            row(
                "Awakenings", "\(context.night.wakeCount)",
                definitionTitle: "Awakenings", definitionSymbol: "eye",
                definition: [
                    "Meaningful wake periods after you first fell asleep, not counting brief stirs before sleep onset. Everyone wakes briefly several times a night without remembering it -- this counts the ones long enough to register.",
                    "There's no universal 'normal' count; it's most useful compared against your own recent nights rather than a fixed target."
                ]
            )
        }
        .glassCard()
    }

    // MARK: - Data completeness

    @ViewBuilder
    private var dataCompletenessCard: some View {
        let sources: [(label: String, available: Bool)] = [
            ("Sleep stages", context.night.hasStageBreakdown),
            ("Heart rate", context.night.avgHeartRate != nil),
            ("HRV", context.night.avgHRV != nil),
            ("Respiration", context.night.avgRespiratoryRate != nil),
            ("Wrist temperature", context.night.wristTempDeltaC != nil),
            ("Blood oxygen", context.night.avgSpO2 != nil),
            ("Breathing disturbances", context.night.breathingDisturbances != nil)
        ]

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Tracking Completeness", systemImage: "checklist")
                Spacer()
                Text("\(context.sleepIntelligence.dataCompletenessPercent)%")
                    .font(Theme.label(14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Metric.sleep)
            }
            ForEach(sources, id: \.label) { source in
                HStack {
                    Text(source.label)
                        .font(Theme.label(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: source.available ? "checkmark.circle.fill" : "minus.circle")
                        .font(Theme.text(11))
                        .foregroundStyle(source.available ? Theme.Metric.recoveryHigh : .secondary)
                }
            }
            Text("Missing data is never treated as zero -- a metric with nothing available here is simply left out of tonight's score and comparisons.")
                .font(Theme.text(9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func row(
        _ label: String, _ value: String,
        definitionTitle: String? = nil, definitionSymbol: String = "info.circle",
        definition: [String]? = nil
    ) -> some View {
        HStack {
            Text(label)
                .font(Theme.label(12))
                .foregroundStyle(.secondary)
            if let definitionTitle, let definition {
                MetricInfoButton(
                    title: definitionTitle, symbol: definitionSymbol,
                    tint: Theme.Metric.sleep, explanation: definition
                )
            }
            Spacer()
            Text(value)
                .font(Theme.label(13, weight: .semibold))
                .monospacedDigit()
        }
    }
}

/// Whoop-style sleep need: a stacked bar of what you needed vs what you got.
struct SleepNeedCard: View {
    let need: SleepNeed

    private var color: Color {
        Theme.recoveryColor(need.performancePercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Sleep Need", systemImage: "target")
                Spacer()
                Text("\(Int(need.performancePercent))%")
                    .font(Theme.numeral(26))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            // Stacked need bar, with an overlay marking what was actually slept.
            GeometryReader { geo in
                let total = max(need.totalNeedMinutes, need.achievedMinutes, 1)

                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(need.contributions) { contribution in
                            Rectangle()
                                .fill(color(for: contribution.kind))
                                .frame(width: geo.size.width * abs(contribution.minutes) / total)
                        }
                    }
                    .clipShape(Capsule())

                    Capsule()
                        .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                        .frame(width: geo.size.width * min(1, need.achievedMinutes / total))
                }
            }
            .frame(height: 22)

            VStack(spacing: 7) {
                ForEach(need.contributions) { contribution in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: contribution.kind))
                            .frame(width: 7, height: 7)
                        Text(contribution.label)
                            .font(Theme.label(12))
                        Spacer()
                        Text(signed(contribution.minutes))
                            .font(Theme.label(12, weight: .semibold))
                            .monospacedDigit()
                    }
                }

                Divider().overlay(Theme.cardStroke)

                HStack {
                    Text("Total need")
                        .font(Theme.label(12, weight: .bold))
                    Spacer()
                    Text(SleepNightFeatures.formatMinutes(need.totalNeedMinutes))
                        .font(Theme.label(12, weight: .bold))
                        .monospacedDigit()
                }
                HStack {
                    Text("You slept")
                        .font(Theme.label(12, weight: .bold))
                    Spacer()
                    Text(SleepNightFeatures.formatMinutes(need.achievedMinutes))
                        .font(Theme.label(12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
            }

            Text(need.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func color(for kind: SleepNeed.Contribution.Kind) -> Color {
        switch kind {
        case .baseline: Theme.Metric.sleep
        case .debt: Theme.Metric.temperature
        case .strain: Theme.Metric.strain
        case .nap: Theme.Metric.battery
        }
    }

    private func signed(_ minutes: Double) -> String {
        let prefix = minutes < 0 ? "−" : "+"
        return prefix + SleepNightFeatures.formatMinutes(abs(minutes))
    }
}

/// Fitbit-style chronotype card.
struct ChronotypeCard: View {
    let chronotype: Chronotype

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: chronotype.kind.symbol)
                    .font(Theme.text(26))
                    .foregroundStyle(Theme.Metric.sleep)
                    .frame(width: 42, height: 42)
                    .background(Theme.Metric.sleep.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("You sleep like a \(chronotype.kind.label)")
                        .font(Theme.label(15, weight: .bold))
                    if chronotype.kind != .unknown {
                        Text("Typical bedtime \(chronotype.formattedBedtime) · ±\(Int(chronotype.consistencyMinutes)) min")
                            .font(Theme.text(11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Text(chronotype.kind.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Sleep detail") {
    NavigationStack {
        SleepDetailView(context: withSegments(AppMockData.dayContext()))
    }
    .preferredColorScheme(.dark)
}

#Preview("Sleep need only") {
    ScrollView {
        VStack(spacing: 16) {
            SleepNeedCard(need: AppMockData.dayContext().sleepNeed)
            SleepNeedCard(need: AppMockData.poorDayContext().sleepNeed)
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

/// Mock nights carry no HealthKit timeline, so previews graft one on.
///
/// Goes through `replacing(night:)` rather than rebuilding the context by
/// hand: the hand-rolled version had to list every field, so adding one broke
/// this file and only announced itself on a CI runner.
private func withSegments(_ context: DayContext) -> DayContext {
    var night = context.night
    night.stageSegments = AppMockData.stageSegments(for: night)
    return context.replacing(night: night)
}
