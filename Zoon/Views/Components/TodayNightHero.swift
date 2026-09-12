import SwiftUI

/// Today's focal object: a moon whose ring is last night versus need.
///
/// Replaces the orbit-first, scores-hidden layout. Sleep duration is the
/// answer; the ring is how full the night was against need; the crescent
/// is the same moon as first-run and the home-screen icon. Tap the moon to
/// open last night. Drag still belongs to `InteractiveMoon`.
struct TodayNightHero: View {
    let context: DayContext
    let greeting: String
    var scoreLight: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsStages = false

    private var fill: CGFloat {
        let need = max(context.sleepNeed.totalNeedMinutes, 1)
        return CGFloat(min(1, max(0, context.night.timeAsleepMinutes / need)))
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("زوٗن")
                    .font(Theme.kicker)
                    .tracking(1.4)
                    .foregroundStyle(Theme.Family.sleep)
                if context.isMock {
                    StatusPill(text: "Sample data", systemImage: "wand.and.stars", tint: Theme.Family.sleep)
                }
                Text(greeting)
                    .font(Theme.label(15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            ZStack {
                NightSky(starCount: 28)
                    .clipShape(Circle())
                    .frame(width: 268, height: 268)
                    .opacity(0.85)

                Circle()
                    .stroke(Theme.neutral(0.14), lineWidth: 10)
                    .frame(width: 236, height: 236)

                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(
                        Theme.Family.sleep,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 236, height: 236)
                    .animation(reduceMotion ? nil : Motion.standard, value: fill)

                InteractiveMoon(size: 168)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(context.night.formattedTimeAsleep) asleep of \(SleepNightFeatures.formatMinutes(context.sleepNeed.totalNeedMinutes)) need"
            )
            .accessibilityAddTraits(.isButton)
            .onTapGesture {
                Haptics.select()
                withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                    showsStages.toggle()
                }
            }

            VStack(spacing: 4) {
                Text("\(context.night.formattedTimeAsleep) asleep")
                    .font(Theme.numeral(28))
                Text("of \(SleepNightFeatures.formatMinutes(context.sleepNeed.totalNeedMinutes)) need")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                if !scoreLight {
                    Text("\(context.sleepIntelligence.confidence.label) · \(context.sleepIntelligence.dataCompletenessPercent)% data coverage")
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            if showsStages {
                stageRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stageRow: some View {
        HStack(spacing: 10) {
            stageChip("Deep", minutes: context.night.deepMinutes, tint: Theme.Stage.deep)
            stageChip("Core", minutes: context.night.coreMinutes, tint: Theme.Stage.core)
            stageChip("REM", minutes: context.night.remMinutes, tint: Theme.Stage.rem)
            stageChip("Wake", minutes: context.night.awakeMinutes, tint: Theme.Stage.awake)
        }
        .font(Theme.text(11, weight: .medium))
    }

    private func stageChip(_ label: String, minutes: Double, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(SleepNightFeatures.formatMinutes(minutes))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Sleep / Need / Debt as filled tracks, not a row of loose numbers.
struct TodayNeedTracks: View {
    let context: DayContext
    /// Nap minutes recorded today, which no stored night carries yet. See
    /// `NapsTodayCard` for why they have to be read live.
    var napMinutesToday: Double = 0

    /// Last night's main sleep plus every nap already credited to it.
    ///
    /// This track showed `timeAsleepMinutes` — main sleep alone — while debt
    /// and need are both computed from `total24hAsleepMinutes`, which counts
    /// naps. So a nap could shrink the shortfall on the Debt line while the
    /// Sleep line above it never moved, and the two tracks disagreed about
    /// the same night.
    private var slept: Double { context.night.total24hAsleepMinutes }

    /// Today's naps come off today's shortfall, and cannot take it below
    /// zero.
    private var debt: Double {
        max(0, (context.night.sleepDebtMinutes ?? 0) - napMinutesToday)
    }
    private var need: Double { max(context.sleepNeed.totalNeedMinutes, 1) }

    var body: some View {
        VStack(spacing: 12) {
            track(
                label: "Sleep",
                value: SleepNightFeatures.formatMinutes(slept),
                fraction: slept / need,
                tint: Theme.Family.sleep,
                destination: SleepDetailView(context: context)
            )

            if napMinutesToday > 0 {
                track(
                    label: "Naps today",
                    value: SleepNightFeatures.formatMinutes(napMinutesToday),
                    fraction: napMinutesToday / need,
                    tint: Theme.Family.recovery,
                    destination: NapView()
                )
            }
            track(
                label: "Need",
                value: SleepNightFeatures.formatMinutes(context.sleepNeed.totalNeedMinutes),
                fraction: 1,
                tint: Theme.Family.circadian,
                destination: SleepNeedView()
            )
            track(
                label: "Debt",
                value: debt > 1 ? SleepNightFeatures.formatMinutes(debt) : "None",
                fraction: min(1, debt / need),
                tint: debt > 1 ? Theme.Family.attention : Theme.Family.recovery,
                destination: SleepDebtView()
            )
        }
    }

    private func track<D: View>(
        label: String,
        value: String,
        fraction: Double,
        tint: Color,
        destination: D
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                        .font(Theme.label(12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Text(value)
                        .font(Theme.label(15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.neutral(0.08))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                    }
                }
                .frame(height: 7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(label)")
    }
}

#Preview("Today hero") {
    TodayView().zoonPreviewEnvironment()
}
