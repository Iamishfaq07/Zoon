import SwiftUI
import UIKit

/// The morning screen: recovery, what to do about it, and why.
///
/// Ordered by what someone actually wants at 7am — the verdict first, the
/// prescription immediately under it, and the evidence below that. Nobody opens
/// a recovery app to browse; they open it to find out whether to train.
struct TodayView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    // Owned locally rather than read fresh from `coordinator.journal` on
    // every render: a tap saved through the store and re-fetched wouldn't
    // reliably trigger a SwiftUI update on its own -- same reasoning as
    // JournalView's `selectedTagIdentifiers`, see that type's doc comment.
    @State private var checkInFeeling: MorningFeeling?
    @State private var checkInDetails: [CheckInDimension: Int] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal)
                    .padding(.bottom, 28)
            }
            .nightBackground()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .zoonGlobalToolbar()
            .refreshable { await coordinator.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.state {
        case .idle, .loading:
            LoadingState()
        case let .loaded(context), let .mock(context):
            loadedContent(context)
        case let .empty(reason):
            EmptyState(reason: reason) { Task { await coordinator.refresh() } }
        case let .failed(message):
            ErrorState(message: message) { Task { await coordinator.refresh() } }
        }
    }

    private func loadedContent(_ context: DayContext) -> some View {
        // Indices drive the entrance cascade — see Motion.stagger. Written out
        // rather than derived, because the order is a design decision and a
        // reader should be able to see it.
        VStack(spacing: Theme.stackSpacing) {
            if coordinator.recentNights.count <= 1 {
                FirstNightCard(night: context.night).entrance(0)
            } else {
                morningBrief(context).entrance(0)
                FloatingMetricCluster(
                    timeAsleepMinutes: context.night.timeAsleepMinutes,
                    needMinutes: context.sleepNeed.totalNeedMinutes,
                    debtMinutes: context.night.sleepDebtMinutes ?? 0
                ).entrance(1)
            }
            MorningCheckInCard(
                selected: checkInFeeling,
                details: checkInDetails,
                onSelectFeeling: { feeling in
                    checkInFeeling = feeling
                    coordinator.journal.setFeeling(feeling, on: context.night.date)
                },
                onSelectDetail: { dimension, value in
                    checkInDetails[dimension] = value
                    coordinator.journal.setCheckIn(dimension, value: value, on: context.night.date)
                }
            )
            .entrance(1)
            .task(id: context.night.date) {
                let entry = coordinator.journal.entry(for: context.night.date)
                checkInFeeling = entry?.feeling
                checkInDetails = CheckInDimension.allCases.reduce(into: [:]) { result, dimension in
                    result[dimension] = entry?.value(for: dimension)
                }
            }
            if let mode = RecoveryMode.evaluate(
                band: context.recovery.band,
                manuallyEnabledToday: preferences.isRecoveryModeManuallyEnabledToday
            ) {
                RecoveryModeCard(mode: mode) {
                    preferences.setRecoveryModeEnabledToday(false)
                }
                .entrance(1)
            } else {
                RecoveryModeEnableLink {
                    preferences.setRecoveryModeEnabledToday(true)
                }
                .entrance(1)
            }
            if let stress = coordinator.todayStress {
                StressCard(stress: stress, todayStrain: context.strain.value).entrance(1)
            }
            ringsCard(context).entrance(2)
            HealthPulseStrip(vitals: context.vitals).entrance(2)
            SleepSummaryStrip(context: context).entrance(3)
            // Tonight's countdown used to live only on the Sleep tab, so the
            // morning screen said nothing about the night still ahead. It's
            // read-only here -- the toggle to turn reminders on lives in
            // Settings, not duplicated onto a card that would need its own
            // permission-request path to make a toggle here mean anything.
            BedtimeCountdownCard().entrance(3)
            if let bedtime = context.targetBedtime() {
                TonightTimelineCard(
                    windDown: bedtime.addingTimeInterval(-Double(BedtimeReminder.windDownLeadMinutes) * 60),
                    bedtime: bedtime,
                    wake: context.bodyClock?.window(for: .now)?.end
                ).entrance(3)
            }
            if coordinator.recentNights.count < 30 {
                PersonalizationProgressCard(
                    nightsTracked: coordinator.recentNights.count,
                    taggedNights: coordinator.journal.taggedNightCount()
                ).entrance(4)
            }
            EnergyForecastCard(forecast: EnergyForecast.compute(
                wakeTime: context.night.wakeTime,
                sleepDebtMinutes: context.night.sleepDebtMinutes ?? 0,
                windDownHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil
            )).entrance(5)
            if let lightGuidance = LightCoach.guidance(
                wakeTime: context.night.wakeTime,
                onsetHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil,
                todayDaylightMinutes: preferences.lifestyleInsightsEnabled
                    ? coordinator.todayLifestyleInsights?.daylightMinutes : nil
            ) {
                LightCoachCard(guidance: lightGuidance).entrance(5)
            }
            BodyBatteryCard(battery: context.bodyBattery).entrance(5)
            // Radar first among the diagnostics: a sustained multi-signal drift
            // is the rarest and most consequential thing on this screen, and it
            // renders as nothing at all when there's nothing to say.
            HealthRadarCard(radar: context.healthRadar).entrance(6)
            RecoveryBreakdownCard(recovery: context.recovery).entrance(7)
            VitalsCard(vitals: context.vitals).entrance(8)
            HRVStatusCard(status: context.hrvStatus).entrance(8)
            RegularityCard(regularity: context.regularity).entrance(8)
            // Cardiovascular Age deliberately isn't here: it's an
            // internally-invented formula, not a validated clinical measure,
            // and sitting beside baseline-derived cards like Recovery lent it
            // a credibility it hasn't earned. It lives in Insights → Labs.
            InsightCard(
                insight: context.insight,
                engineName: context.insight.source.displayName,
                night: context.night
            )
            .entrance(8)
            footer(context).entrance(8)
        }
    }

    // MARK: - Morning brief

    /// Sleep Intelligence, not Recovery, leads the screen -- "how did I
    /// sleep" is the more fundamental question, and Recovery ("how
    /// recovered does my body look") keeps its own place further down at
    /// `RecoveryBreakdownCard`. `context.headline` is still Recovery-derived
    /// text ("You're recovered", "You need to take it easy"); it reads fine
    /// as the supporting line under the new hero since `guidanceCard`
    /// immediately below spells out what to actually do about it.
    private func morningBrief(_ context: DayContext) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if context.isMock {
                StatusPill(text: "Sample data", systemImage: "wand.and.stars", tint: Theme.Metric.sleep)
            }

            HStack(alignment: .center, spacing: 18) {
                SleepIntelligenceOrb(
                    score: context.sleepIntelligence,
                    size: 156,
                    lineWidth: 12
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("Morning brief")
                        .font(Theme.label(12, weight: .bold))
                        .foregroundStyle(.tertiary)

                    Text(context.headline)
                        .font(Theme.label(18, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    // `MetricConfidence.label` already reads "Moderate
                    // confidence" / "High confidence" -- appending the word
                    // again rendered "Moderate confidence confidence" in the
                    // hero card, and "Insufficient data confidence" for the
                    // no-data case.
                    Text("\(context.sleepIntelligence.confidence.label) · \(context.sleepIntelligence.dataCompletenessPercent)% data coverage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if context.recovery.isEstimate {
                Text("Zoon needs a few more nights before this number is trustworthy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !context.sleepIntelligence.components.isEmpty {
                Divider().overlay(Theme.cardStroke)
                WhyScoreWaterfall(components: context.sleepIntelligence.components)
            }

            Divider().overlay(Theme.cardStroke)
            VStack(alignment: .leading, spacing: 5) {
                Label("One action for tonight", systemImage: "checkmark.circle.fill")
                    .font(Theme.label(12, weight: .bold))
                    .foregroundStyle(Theme.recoveryColor(Double(context.recovery.percent)))
                Text(context.insight.actionableTip)
                    .font(Theme.label(14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    // MARK: - Rings

    private func ringsCard(_ context: DayContext) -> some View {
        AdaptiveStack(spacing: 16) {
            TripleRing(arcs: [
                .init(
                    fraction: context.strain.value / StrainScore.maxValue,
                    color: Theme.Metric.strain,
                    label: "Load", value: context.strain.displayValue
                ),
                .init(
                    fraction: context.sleepNeed.performancePercent / 100,
                    color: Theme.Metric.sleep,
                    label: "Sleep", value: "\(Int(context.sleepNeed.performancePercent))%"
                ),
                .init(
                    fraction: Double(context.bodyBattery.current) / 100,
                    color: Theme.Metric.battery,
                    label: "Energy", value: "\(context.bodyBattery.current)"
                )
            ])

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    metricRow(
                        "Load", context.strain.displayValue,
                        detail: context.strain.band, color: Theme.Metric.strain,
                        caveat: context.strain.isEstimate ? "estimated" : nil
                    )
                    Spacer(minLength: 4)
                    MetricInfoButton(
                        title: "Daily Load",
                        symbol: "flame.fill",
                        tint: Theme.Metric.strain,
                        explanation: [
                            "Daily Load is a cardiovascular load score built from your heart rate through the day, weighted by how far above resting it ran and for how long -- not just a step count or a workout minutes total.",
                            "It's read next to Sleep Need and Recovery deliberately: a high-load day increases what your body needs from that night's sleep to fully recover."
                        ]
                    )
                }

                NavigationLink {
                    SleepDetailView(context: context)
                } label: {
                    HStack(spacing: 8) {
                        metricRow(
                            "Sleep", "\(Int(context.sleepNeed.performancePercent))%",
                            detail: context.sleepNeed.performanceBand, color: Theme.Metric.sleep
                        )
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(Theme.text(11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    metricRow(
                        "Energy", "\(context.bodyBattery.current)",
                        detail: context.bodyBattery.band, color: Theme.Metric.battery
                    )
                    Spacer(minLength: 4)
                    MetricInfoButton(
                        title: "Energy Reserve",
                        symbol: "bolt.fill",
                        tint: Theme.Metric.battery,
                        explanation: [
                            "Energy Reserve models how much you have left through the day: it fills overnight based on how restorative your sleep was, then drains with activity and stress signals as the day goes on.",
                            "It's a same-day curve, not a rolling average -- see the full shape of today in the Energy Reserve card below."
                        ]
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
    }

    private func metricRow(
        _ title: String, _ value: String,
        detail: String, color: Color, caveat: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(value)
                        .font(Theme.label(17, weight: .bold))
                        .monospacedDigit()
                    Text(title)
                        .font(Theme.label(11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text(detail)
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                    if let caveat {
                        Text("· \(caveat)")
                            .font(Theme.text(10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func footer(_ context: DayContext) -> some View {
        VStack(spacing: 3) {
            if let source = context.night.sourceName {
                // "Sleep source", not "Source": this names which HealthKit
                // source the sleep-*stage* samples came from (see
                // SleepNightFeatures.sourceName), not a claim that every
                // vital on screen came from the same device -- HR, HRV, RHR,
                // etc. are queried across whatever sources HealthKit has for
                // that time window, independent of which source won the
                // stage data. A bare "Source: X" here read as broader
                // provenance than the app actually tracks.
                Text("Sleep source: \(source)")
            }
            if let last = coordinator.lastRefresh {
                Text("Updated \(last, format: .dateTime.hour().minute())")
            }
        }
        .font(Theme.text(10))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: - Cards

struct BodyBatteryCard: View {
    let battery: BodyBattery

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Energy Reserve", systemImage: "bolt.fill")
                Spacer()
                MetricInfoButton(
                    title: "Energy Reserve",
                    symbol: "bolt.fill",
                    tint: Theme.Metric.battery,
                    explanation: [
                        "Fills overnight based on how restorative your sleep was, then drains through the day with activity and stress signals -- a same-day curve, not a running average.",
                        "Tap and drag anywhere on the chart below to see the exact level at any point in the day."
                    ]
                )
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(battery.current)")
                        .font(Theme.numeral(28))
                        .monospacedDigit()
                        .foregroundStyle(Theme.batteryColor(Double(battery.current)))
                    Text("/100")
                        .font(Theme.label(12))
                        .foregroundStyle(.tertiary)
                }
            }

            BodyBatteryChart(battery: battery)

            AdaptiveStack(spacing: 14) {
                stat("Woke at", "\(battery.morningPeak)")
                stat("Spent", "\(battery.spentToday)")
                stat("Low", "\(battery.dayLow)")
            }

            Text(battery.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.label(15, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact sleep row on Today; the full breakdown lives on the Sleep tab.
struct SleepSummaryStrip: View {
    let context: DayContext

    var body: some View {
        NavigationLink {
            SleepDetailView(context: context)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Last Night", systemImage: "moon.stars.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(context.night.formattedTimeAsleep)
                        .font(Theme.numeral(34))
                        .monospacedDigit()
                    Text("\(Int(context.sleepNeed.performancePercent))% of need")
                        .font(Theme.label(13))
                        .foregroundStyle(.secondary)
                }

                if !context.night.stageSegments.isEmpty {
                    HypnogramView(
                        segments: context.night.stageSegments,
                        height: 74,
                        showsAxis: false
                    )
                } else {
                    StageProportionBar(features: context.night)
                }
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

/// Shows the recovery score's working — which input dragged it where.
struct RecoveryBreakdownCard: View {
    let recovery: RecoveryScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "What drove your recovery",
                    subtitle: "Each input measured against your own baseline, not a population average.",
                    systemImage: "chart.bar.doc.horizontal"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Recovery Score",
                    symbol: "chart.bar.doc.horizontal",
                    tint: Theme.recoveryColor(Double(recovery.percent)),
                    explanation: [
                        "Recovery blends several signals -- HRV, resting heart rate, and sleep performance among them -- each compared against your own baseline rather than a fixed target.",
                        "The bars above show how much each input pulled the score up or down. A signal with nothing to measure tonight (no reading, or no baseline yet) is left out entirely and its weight redistributes among the rest -- it's never scored as average or assumed fine."
                    ]
                )
            }

            ForEach(recovery.components) { component in
                HStack(spacing: 10) {
                    Text(component.label)
                        .font(Theme.label(12, weight: .medium))
                        .foregroundStyle(component.isAvailable ? .primary : .tertiary)
                        .frame(width: 82, alignment: .leading)

                    if component.isAvailable {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.neutral(0.08))
                                Capsule()
                                    .fill(Theme.recoveryColor(component.normalized * 100))
                                    .frame(width: geo.size.width * min(1, max(0.02, component.normalized)))
                            }
                        }
                        .frame(height: 7)
                    } else {
                        // Not a zero-width or zero-value bar: that would read
                        // as "scored badly" rather than "wasn't measured."
                        Capsule()
                            .strokeBorder(Theme.neutral(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(height: 7)
                    }

                    Text(component.isAvailable ? component.detail : "Not available")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 74, alignment: .trailing)

                    if let deviation = component.deviationPercent, component.isAvailable {
                        Text(String(format: "%+.0f%%", deviation))
                            .font(Theme.text(10, weight: .semibold))
                            .foregroundStyle(deviation >= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
                            .frame(width: 40, alignment: .trailing)
                    } else {
                        Spacer().frame(width: 40)
                    }
                }
            }

            if recovery.dataCompletenessPercent < 100 {
                Divider().overlay(Theme.cardStroke)
                Text("Based on \(recovery.availableComponentCount) of \(recovery.components.count) signals tonight (\(recovery.dataCompletenessPercent)% of the full model). Missing signals were excluded, not assumed average.")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }
}

/// Apple-Health-style vitals panel: typical vs outlier.
struct VitalsCard: View {
    let vitals: VitalsStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(title: "Vitals", subtitle: vitals.detail, systemImage: "waveform.path.ecg")
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Vitals",
                    symbol: "waveform.path.ecg",
                    tint: Theme.Metric.recoveryHigh,
                    explanation: [
                        "Each row compares last night's reading against the typical range Zoon has built from your own recent history -- not a clinical or population range.",
                        "A single reading outside the typical range is common and usually not meaningful on its own. It's worth attention mainly if several nights in a row land outside it."
                    ]
                )
                StatusPill(
                    text: vitals.outliers.isEmpty ? "Typical" : "\(vitals.outliers.count)",
                    systemImage: vitals.outliers.isEmpty ? "checkmark" : "exclamationmark",
                    tint: vitals.outliers.isEmpty ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid
                )
            }

            ForEach(vitals.metrics) { metric in
                VitalRow(metric: metric)
            }

            Text(SleepInsight.disclaimer)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

private struct VitalRow: View {
    let metric: VitalsStatus.Metric

    private var tint: Color {
        switch metric.state {
        case .typical: Theme.Metric.recoveryHigh
        case .aboveTypical, .belowTypical: Theme.Metric.recoveryMid
        case .unavailable: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: metric.kind.symbol)
                .font(Theme.text(12))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.kind.label)
                    .font(Theme.label(12, weight: .medium))
                if let range = metric.formattedRange {
                    Text("Typical \(range)")
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(metric.formattedValue)
                .font(Theme.label(13, weight: .semibold))
                .monospacedDigit()

            Image(systemName: metric.state.symbol)
                .font(Theme.text(11))
                .foregroundStyle(tint)
                .frame(width: 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.kind.label)
        .accessibilityValue("\(metric.formattedValue), \(metric.state.label)")
    }
}

/// Garmin-style HRV status: the week against the quarter.
struct HRVStatusCard: View {
    let status: HRVStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "HRV Status", systemImage: "heart.text.square")
                Spacer()
                MetricInfoButton(
                    title: "HRV Status",
                    symbol: "heart.text.square",
                    tint: tint,
                    explanation: [
                        "This compares your HRV this week against your own rolling quarterly range, not a population average -- what's balanced for you can be a meaningful drop for someone else.",
                        "It needs a few weeks of nights before the range is trustworthy, and one low night on its own is normal noise, not a signal."
                    ],
                    relatedArticleID: "hrv-explained"
                )
                StatusPill(text: status.state.label, tint: tint)
            }

            if let weekly = status.weeklyAverage,
               let lower = status.lowerBound,
               let upper = status.upperBound {

                // Pad the plotted range beyond the balanced band so a weekly
                // average sitting outside it still lands on the gauge.
                let span = max(upper - lower, 1)
                let plotMin = lower - span
                let plotMax = upper + span

                RangeGauge(
                    position: (weekly - plotMin) / (plotMax - plotMin),
                    bandStart: (lower - plotMin) / (plotMax - plotMin),
                    bandEnd: (upper - plotMin) / (plotMax - plotMin),
                    tint: tint
                )

                HStack {
                    Text("\(Int(weekly)) ms this week")
                        .font(Theme.label(12, weight: .semibold))
                        .monospacedDigit()
                    Spacer()
                    Text("Your range \(Int(lower))–\(Int(upper)) ms")
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            Text(status.state.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var tint: Color {
        switch status.state {
        case .balanced: Theme.Metric.recoveryHigh
        case .unbalanced: Theme.Metric.recoveryMid
        case .low: Theme.Metric.temperature
        case .poor: Theme.Metric.recoveryLow
        case .building: .secondary
        }
    }
}

// MARK: - States

struct LoadingState: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Reading last night…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }
}

/// Shown when queries succeeded but found nothing.
///
/// This screen exists because the failure mode it replaces — an eternal spinner
/// — is indistinguishable from a hang, and HealthKit gives us no way to tell the
/// user "you denied permission". So it names both plausible causes and offers a
/// direct route to Settings.
struct EmptyState: View {
    let reason: SleepDataCoordinator.EmptyReason
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(reason.title, systemImage: "moon.zzz")
        } description: {
            Text(reason.message)
        } actions: {
            if reason == .noSleepData {
                Button("Open Health Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Check Again", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(.top, 40)
    }
}

struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't read your sleep", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }
}

#Preview("Today") {
    TodayView().zoonPreviewEnvironment()
}
