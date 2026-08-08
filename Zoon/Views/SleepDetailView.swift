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
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
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
            row("Time in bed", SleepNightFeatures.formatMinutes(context.night.timeInBedMinutes))
            row("Efficiency", "\(Int(context.night.sleepEfficiencyPercent))%")
            if let latency = context.night.sleepLatencyMinutes {
                row("Fell asleep in", "\(Int(latency)) min")
            }
            row("Awakenings", "\(context.night.wakeCount)")
        }
        .glassCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.label(12))
                .foregroundStyle(.secondary)
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
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Metric.sleep)
                    .frame(width: 42, height: 42)
                    .background(Theme.Metric.sleep.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("You sleep like a \(chronotype.kind.label)")
                        .font(Theme.label(15, weight: .bold))
                    if chronotype.kind != .unknown {
                        Text("Typical bedtime \(chronotype.formattedBedtime) · ±\(Int(chronotype.consistencyMinutes)) min")
                            .font(.system(size: 11))
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
private func withSegments(_ context: DayContext) -> DayContext {
    var night = context.night
    night.stageSegments = AppMockData.stageSegments(for: night)
    return DayContext(
        night: night, insight: context.insight, recovery: context.recovery,
        sleepNeed: context.sleepNeed, sleepScore: context.sleepScore,
        strain: context.strain, bodyBattery: context.bodyBattery,
        vitals: context.vitals, hrvStatus: context.hrvStatus,
        chronotype: context.chronotype
    )
}
