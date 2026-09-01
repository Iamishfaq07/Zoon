import SwiftUI

/// One insight, one action, and a "Why?" that opens the working.
///
/// Consolidates what used to be three separate Today blocks -- the
/// `InsightCard` (summary/cause/tip), `briefCard` (waterfall + "one action")
/// and `context.headline` -- into a single editorial block. All three read
/// the same `SleepInsight` and `SleepIntelligenceScore`; nothing is
/// re-derived. The waterfall is unchanged, just behind a disclosure.
///
/// No card. Typography carries the hierarchy: kicker, headline sentence,
/// then the action set off by a rule.
struct MorningBrief: View {
    let context: DayContext

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZoonSectionHeader("Your morning brief") {
                Text(context.insight.source.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(context.insight.summary)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let cause = context.insight.likelyCause, context.insight.confidence > .low {
                Text(cause)
                    .font(Theme.text(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Best move today")
                    .font(Theme.kicker)
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Family.sleep)
                Text(context.insight.actionableTip)
                    .font(Theme.label(15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Capsule().fill(Theme.Family.sleep.opacity(0.6)).frame(width: 2)
            }

            HStack(spacing: 16) {
                if !context.sleepIntelligence.components.isEmpty {
                    ZoonExplainThenDetail(
                        explanation: "",
                        detailLabel: "Why this score?"
                    ) {
                        WhyScoreWaterfall(components: context.sleepIntelligence.components, context: context)
                            .padding(.top, 4)
                    }
                }

                NavigationLink {
                    CoachChatView(night: context.night)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Ask a follow-up")
                    }
                    .font(Theme.text(11, weight: .semibold))
                    .foregroundStyle(Theme.Family.sleep)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }

            if context.recovery.isEstimate {
                Text("Zoon needs a few more nights before these numbers are trustworthy.")
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Morning Brief") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 32) {
                MorningBrief(context: AppMockData.dayContext())
                MorningBrief(context: AppMockData.poorDayContext())
            }
            .padding()
        }
        .nightBackground()
    }
    .zoonPreviewEnvironment()
}
