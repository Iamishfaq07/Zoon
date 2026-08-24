import SwiftUI

/// This week against the week before it, in the same four numbers the charts
/// further down the tab already track -- sleep time, HRV, bedtime steadiness,
/// and accumulated debt. The charts show shape over time; this answers the one
/// question people actually open Insights to ask first: "is this week better
/// or worse than last week?"
///
/// Needs 14 nights of history to compare two full weeks. Below that it
/// renders nothing, same as `TrendsView`'s own not-enough-data gate for the
/// charts -- a half-populated comparison would be misleading, not just bare.
struct WhatChangedCard: View {
    /// Full stored history, oldest first (`SleepDataCoordinator.recentNights`),
    /// not the tab's 7/30-day display slice -- the previous-week comparison
    /// needs up to 14 nights regardless of which window is currently picked.
    let nights: [SleepNightFeatures]
    let goalMinutes: Double

    private struct Row: Identifiable {
        let label: String
        let symbol: String
        let formatted: String
        let isImprovement: Bool?
        var id: String { label }
    }

    private var currentWeek: [SleepNightFeatures] { Array(nights.suffix(7)) }
    private var previousWeek: [SleepNightFeatures] {
        Array(nights.dropLast(7).suffix(7))
    }

    private var rows: [Row]? {
        guard currentWeek.count == 7, previousWeek.count == 7 else { return nil }

        var result: [Row] = []

        let sleepDelta = average(currentWeek.map(\.timeAsleepMinutes)) - average(previousWeek.map(\.timeAsleepMinutes))
        result.append(Row(
            label: "Time asleep",
            symbol: "bed.double.fill",
            formatted: signedMinutes(sleepDelta),
            isImprovement: sleepDelta == 0 ? nil : sleepDelta > 0
        ))

        let currentHRV = currentWeek.compactMap(\.avgHRV)
        let previousHRV = previousWeek.compactMap(\.avgHRV)
        if currentHRV.count >= 2, previousHRV.count >= 2 {
            let hrvDelta = average(currentHRV) - average(previousHRV)
            result.append(Row(
                label: "HRV",
                symbol: "waveform.path.ecg",
                formatted: "\(hrvDelta >= 0 ? "+" : "")\(Int(hrvDelta.rounded())) ms",
                isImprovement: hrvDelta == 0 ? nil : hrvDelta > 0
            ))
        }

        let consistencyDelta = bedtimeStandardDeviationMinutes(previousWeek) - bedtimeStandardDeviationMinutes(currentWeek)
        result.append(Row(
            label: "Bedtime steadiness",
            symbol: "clock.arrow.2.circlepath",
            formatted: consistencyDelta == 0
                ? "No change"
                : "\(Int(abs(consistencyDelta).rounded()))m \(consistencyDelta > 0 ? "steadier" : "more scattered")",
            isImprovement: consistencyDelta == 0 ? nil : consistencyDelta > 0
        ))

        let series = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: nights.map(\.total24hAsleepMinutes),
            goalMinutesOldestFirst: nights.map { $0.sleepNeedBaselineMinutes ?? goalMinutes }
        )
        if series.count >= 14, let debtNow = series.last, let debtWeekAgo = series.dropLast(7).last {
            let debtDelta = debtNow - debtWeekAgo
            result.append(Row(
                label: "Sleep debt",
                symbol: "chart.line.downtrend.xyaxis",
                formatted: debtDelta == 0
                    ? "No change"
                    : "\(signedMinutes(-debtDelta)) owed",
                isImprovement: debtDelta == 0 ? nil : debtDelta < 0
            ))
        }

        // Capped at 3 -- the redesign audit found this card could show 4
        // rows (sleep time, HRV, bedtime steadiness, sleep debt) when the
        // spec caps it at 3. Debt is the one most likely to drop off the
        // end since it alone needs a full 14-night series where the other
        // three don't.
        return Array(result.prefix(3))
    }

    var body: some View {
        if let rows {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "What Changed", systemImage: "arrow.left.arrow.right")
                Text("This week vs the week before")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)

                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.symbol)
                            .font(Theme.text(13))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(row.label)
                            .font(Theme.label(13, weight: .medium))
                        Spacer()
                        Text(row.formatted)
                            .font(Theme.label(13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(tint(for: row.isImprovement))
                    }
                }
            }
            .glassCard()
        }
    }

    private func tint(for isImprovement: Bool?) -> Color {
        switch isImprovement {
        case true: Theme.Metric.recoveryHigh
        case false: Theme.Metric.recoveryMid
        case nil: .secondary
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func signedMinutes(_ minutes: Double) -> String {
        guard minutes != 0 else { return "No change" }
        let magnitude = Int(abs(minutes).rounded())
        return "\(minutes > 0 ? "+" : "-")\(magnitude)m"
    }

    /// Standard deviation of bedtime, in minutes, shifted so evening times
    /// don't wrap around midnight -- the same convention `ConsistencyChartCard`
    /// uses for its Y axis, recomputed here rather than shared because that
    /// helper is `private` to a view built around a very different shape.
    private func bedtimeStandardDeviationMinutes(_ week: [SleepNightFeatures]) -> Double {
        let calendar = Calendar.current
        let minutesFromMidnight = week.map { night -> Double in
            let components = calendar.dateComponents([.hour, .minute], from: night.bedtime)
            let minutes = Double(components.hour ?? 0) * 60 + Double(components.minute ?? 0)
            return minutes >= 18 * 60 ? minutes - 24 * 60 : minutes
        }
        guard minutesFromMidnight.count > 1 else { return 0 }
        let mean = average(minutesFromMidnight)
        let variance = minutesFromMidnight.reduce(0) { $0 + pow($1 - mean, 2) } / Double(minutesFromMidnight.count)
        return variance.squareRoot()
    }
}

/// The strongest one or two patterns Cause Finder has found in your own
/// history, surfaced here rather than left waiting to be found by tapping
/// into the hub -- the whole point of a finding worth calling a "discovery"
/// is that you didn't go looking for it. Reuses `JournalCorrelator` directly,
/// the same engine and the same findings Cause Finder's Helps/Hurts tabs list
/// in full; this is a preview of that screen, not a second opinion.
struct DiscoveriesCard: View {
    let findings: [JournalCorrelator.Finding]
    /// The behaviour currently under a Guided Experiment, and where it
    /// stands -- `nil` when no experiment is active. Surfaced here too, not
    /// just inside Cause Finder, since a resolved experiment ("Alcohol
    /// costs you 12min of deep sleep") is exactly the kind of thing this
    /// card exists to surface rather than leave waiting behind a tap.
    var activeExperiment: (tag: BehaviorTag, status: GuidedExperiment.Status)? = nil

    private var top: [JournalCorrelator.Finding] {
        Array(
            findings.sorted {
                $0.confidence.rank == $1.confidence.rank
                    ? $0.matchedPairCount > $1.matchedPairCount
                    : $0.confidence.rank > $1.confidence.rank
            }
            .prefix(2)
        )
    }

    private var experimentHeadline: (text: String, isImprovement: Bool?)? {
        guard let activeExperiment else { return nil }
        switch activeExperiment.status {
        case .learning:
            return ("Experiment: \(activeExperiment.tag.label) -- still learning", nil)
        case .result(let helpful, let harmful):
            if let strongest = (helpful + harmful).first {
                return (strongest.headline, strongest.isImprovement)
            }
            return nil
        case .noEffect:
            return ("Experiment: \(activeExperiment.tag.label) -- no meaningful difference found so far", nil)
        }
    }

    var body: some View {
        if !top.isEmpty || experimentHeadline != nil {
            NavigationLink {
                CauseFinderView()
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Discoveries", systemImage: "sparkle.magnifyingglass")
                    ForEach(top) { finding in
                        HStack(spacing: 10) {
                            Image(systemName: finding.tag.symbol)
                                .font(Theme.text(13))
                                .foregroundStyle(finding.isImprovement ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                                .frame(width: 20)
                            Text(finding.headline)
                                .font(Theme.text(12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                    if let experimentHeadline {
                        HStack(spacing: 10) {
                            Image(systemName: "flask.fill")
                                .font(Theme.text(13))
                                .foregroundStyle(
                                    experimentHeadline.isImprovement.map { $0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow }
                                        ?? Theme.Metric.sleep
                                )
                                .frame(width: 20)
                            Text(experimentHeadline.text)
                                .font(Theme.text(12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            .buttonStyle(PressableStyle())
        }
    }
}

private extension JournalCorrelator.Confidence {
    var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }
}

#Preview("What Changed") {
    ScrollView {
        VStack(spacing: 16) {
            WhatChangedCard(nights: MockData.history, goalMinutes: 480)
        }
        .padding()
    }
    .nightBackground()
}
