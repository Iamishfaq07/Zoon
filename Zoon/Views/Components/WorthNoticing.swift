import SwiftUI

/// Today's one conditional slot: the single most notable thing that isn't
/// already in the hero, the pulse or the plan.
///
/// Replaces five always-present cards (`HealthRadarCard`, `StressCard`,
/// `RecoveryModeCard`, `LightCoachCard`, `PersonalizationProgressCard`) with
/// a priority-ordered pick. Each candidate's *detection* logic is untouched
/// -- `HealthRadar.detect`, `StressScore.compute`, `RecoveryMode.evaluate`,
/// `LightCoach.guidance` all run exactly as before; this only decides which
/// one gets the morning's attention. Everything not shown here is one tap
/// away on its own screen, so nothing is hidden, only ranked.
///
/// The order is by consequence: a multi-signal drift over several nights
/// beats today's load, which beats a same-day mode, which beats a
/// twice-a-day light nudge, which beats the cold-start progress note.
struct WorthNoticing: View {
    let context: DayContext
    let stress: StressScore?
    let recoveryMode: RecoveryMode?
    let lightGuidance: LightCoach.Guidance?
    let nightsTracked: Int
    let taggedNights: Int
    var onTurnOffRecoveryMode: () -> Void = {}

    enum Item {
        case radar(HealthRadar)
        case stress(StressScore)
        case recoveryMode(RecoveryMode)
        case light(LightCoach.Guidance)
        case learning(nightsTracked: Int, taggedNights: Int)
    }

    /// The pick. `nil` when nothing clears the bar -- then the slot renders
    /// nothing at all, which is the correct answer on an ordinary good day.
    var item: Item? {
        if context.healthRadar.isActive { return .radar(context.healthRadar) }
        if let stress, stress.band != .calm { return .stress(stress) }
        if let recoveryMode { return .recoveryMode(recoveryMode) }
        if let lightGuidance { return .light(lightGuidance) }
        if nightsTracked < 30 { return .learning(nightsTracked: nightsTracked, taggedNights: taggedNights) }
        return nil
    }

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 12) {
                ZoonSectionHeader("Worth noticing")
                content(for: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func content(for item: Item) -> some View {
        switch item {
        case let .radar(radar):
            notice(
                symbol: "dot.radiowaves.left.and.right",
                tint: radar.severity == .notable ? Theme.Family.deviation : Theme.Family.attention,
                headline: radar.headline,
                detail: radar.detail,
                linkLabel: "View Body Signals"
            ) { HealthRadarView() }

        case let .stress(stress):
            notice(
                symbol: "waveform.path.ecg",
                tint: stress.band == .high ? Theme.Family.deviation : Theme.Family.attention,
                headline: "Your body is running \(stress.band == .high ? "well above" : "a bit above") its usual load today",
                detail: stress.band.detail,
                linkLabel: "View today's load"
            ) { StressDetailView(stress: stress, todayStrain: context.strain.value) }

        case let .recoveryMode(mode):
            VStack(alignment: .leading, spacing: 8) {
                noticeText(symbol: "leaf.fill", tint: Theme.Family.recovery, headline: mode.headline, detail: mode.detail)
                if mode.isDismissible {
                    Button("Turn off for today", action: onTurnOffRecoveryMode)
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(Theme.Family.recovery)
                        .buttonStyle(.plain)
                }
            }

        case let .light(guidance):
            noticeText(symbol: guidance.symbol, tint: Theme.Family.circadian, headline: guidance.headline, detail: guidance.detail)

        case let .learning(nights, tagged):
            VStack(alignment: .leading, spacing: 8) {
                noticeText(
                    symbol: "chart.line.uptrend.xyaxis.circle",
                    tint: Theme.Family.sleep,
                    headline: "Zoon is still learning what normal looks like for you",
                    detail: "Personal baselines are built from your own nights, not other people's. Scores get more trustworthy over the next couple of weeks."
                )
                PersonalizationProgressRows(nightsTracked: nights, taggedNights: tagged)
            }
        }
    }

    private func notice<Destination: View>(
        symbol: String,
        tint: Color,
        headline: String,
        detail: String,
        linkLabel: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            noticeText(symbol: symbol, tint: tint, headline: headline, detail: detail)
            NavigationLink(destination: destination) {
                HStack(spacing: 4) {
                    Text(linkLabel)
                    Image(systemName: "chevron.right")
                        .font(Theme.text(10, weight: .semibold))
                }
                .font(Theme.text(12, weight: .semibold))
                .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
        }
    }

    private func noticeText(symbol: String, tint: Color, headline: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(Theme.text(14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(Theme.label(15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Theme.evidence)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The progress rows from `PersonalizationProgressCard`, without the card,
/// so the same thresholds show inside the Worth Noticing slot.
struct PersonalizationProgressRows: View {
    let nightsTracked: Int
    let taggedNights: Int

    private var rows: [(label: String, current: Int, target: Int)] {
        [
            ("Sleep timing", nightsTracked, SleepRegularity.minimumNights),
            ("Recovery baseline", nightsTracked, RecoveryScore.minimumBaselineNights),
            ("Body Clock", nightsTracked, BodyClock.minimumNights),
            ("Cause Finder", taggedNights, JournalCorrelator.minimumMatchedPairs)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.filter { $0.current < $0.target }, id: \.label) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(Theme.text(12))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.neutral(0.08))
                            Capsule()
                                .fill(Theme.Family.sleep.opacity(0.7))
                                .frame(width: geo.size.width * min(1, Double(row.current) / Double(max(row.target, 1))))
                        }
                    }
                    .frame(height: 4)
                    Text("\(row.current)/\(row.target)")
                        .font(Theme.text(11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label), \(row.current) of \(row.target) nights")
            }
        }
        .padding(.leading, 38)
    }
}

#Preview("Worth noticing") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 36) {
                WorthNoticing(context: AppMockData.poorDayContext(), stress: nil, recoveryMode: nil, lightGuidance: nil, nightsTracked: 40, taggedNights: 20)
                WorthNoticing(context: AppMockData.dayContext(), stress: AppMockData.stress, recoveryMode: nil, lightGuidance: nil, nightsTracked: 40, taggedNights: 20)
                WorthNoticing(context: AppMockData.dayContext(), stress: nil, recoveryMode: nil, lightGuidance: nil, nightsTracked: 9, taggedNights: 3)
            }
            .padding()
        }
        .nightBackground()
    }
    .zoonPreviewEnvironment()
}
