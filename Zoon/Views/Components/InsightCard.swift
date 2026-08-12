import SwiftUI

/// Renders a `SleepInsight`.
///
/// Three tiers, because the honest presentation of a guess differs from the
/// honest presentation of a measurement:
///
/// - **summary** — always shown. Factual.
/// - **likelyCause** — shown only when the engine actually identified one, and
///   suppressed at low confidence. Visually distinct so it doesn't read as
///   measured fact.
/// - **actionableTip** — always shown.
struct InsightCard: View {

    let insight: SleepInsight
    var engineName: String?
    /// When set, the card offers a way to ask a follow-up about tonight's
    /// numbers instead of just reading a fixed three-line summary.
    var night: SleepNightFeatures?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(insight.summary)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let cause = insight.likelyCause, insight.confidence > .low {
                Label {
                    Text(cause)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.tint)
                }
                .labelStyle(.topAligned)
            }

            Divider()

            Label {
                Text(insight.actionableTip)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
            }
            .labelStyle(.topAligned)

            if let night {
                NavigationLink {
                    CoachChatView(night: night)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Ask a follow-up")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Theme.text(11, weight: .semibold))
                    }
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(.tint)
            Text("Tonight's Read")
                .font(.headline)
            Spacer()
            if let engineName {
                Text(engineName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Label style that top-aligns the icon with multi-line text.
///
/// The default centres the icon vertically, which looks wrong against a
/// four-line paragraph.
struct TopAlignedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.subheadline)
            configuration.title
        }
    }
}

extension LabelStyle where Self == TopAlignedLabelStyle {
    static var topAligned: TopAlignedLabelStyle { TopAlignedLabelStyle() }
}

#Preview("With cause") {
    ScrollView {
        InsightCard(insight: MockData.poorInsight, engineName: "Rules")
            .padding()
    }
    .nightBackground()
}

#Preview("No cause") {
    ScrollView {
        InsightCard(insight: MockData.goodInsight, engineName: "Rules")
            .padding()
    }
    .nightBackground()
}

#Preview("Live rule engine") {
    // Runs the real engine so a rule change shows up in previews immediately.
    let engine = RuleBasedInsightEngine()
    let baseline = RollingBaseline(
        hrv7DayAvg: 60, sleepDebtMinutes: 340, deep7DayAvg: 74,
        duration7DayAvg: 420, efficiency7DayAvg: 88, minHeartRate7DayAvg: 53,
        wristTempBaselineC: 35.1, bedtimeConsistencyMinutes: 72, sampleCount: 7
    )
    return ScrollView {
        VStack(spacing: 16) {
            InsightCard(
                insight: engine.generate(for: MockData.poorNight, baseline: baseline, goalMinutes: 480),
                engineName: "Rules"
            )
            InsightCard(
                insight: engine.generate(for: MockData.goodNight, baseline: baseline, goalMinutes: 480),
                engineName: "Rules"
            )
        }
        .padding()
    }
    .nightBackground()
}
