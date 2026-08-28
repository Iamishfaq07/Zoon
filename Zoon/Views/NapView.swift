import SwiftUI

/// Nap timer and log.
///
/// Naps matter to this app specifically because they feed `SleepNeed` — a
/// 25-minute nap genuinely reduces tonight's requirement, and a model that
/// ignored them would overstate your debt. HealthKit's own sleep records don't
/// reliably capture short daytime naps, so logging one here fills a real gap.
struct NapView: View {

    @Environment(NapStore.self) private var naps
    @Environment(SleepDataCoordinator.self) private var coordinator

    @State private var selectedMinutes: Int = 20
    @State private var now: Date = .now

    private var recommendation: NapCoach.Recommendation {
        NapCoach.recommend(
            now: now,
            debtMinutes: coordinator.state.context?.night.sleepDebtMinutes ?? 0,
            plannedBedtime: coordinator.state.context?.targetBedtime(now: now),
            napMinutesToday: naps.minutes(on: now)
        )
    }

    /// Nap lengths drawn from the usual general advice about sleep
    /// architecture.
    ///
    /// The copy deliberately no longer claims what *your* nap will do. It
    /// used to: "stays out of deep sleep", "no grogginess", and worst,
    /// "wakes you at the light end" of a cycle. Zoon measures nothing during
    /// a nap — there is no live staging loop, and until this change there
    /// was no wake mechanism at all — so a promise to wake you at a
    /// particular point in a cycle described something the app could not do
    /// even in principle. These are population generalities about typical
    /// nap lengths, and they now read as such.
    private let presets: [(minutes: Int, label: String, detail: String)] = [
        (10, "Short", "Briefest option"),
        (20, "Classic", "The length most commonly suggested"),
        (30, "Long", "Long enough that waking can feel rough"),
        (90, "Full cycle", "About one sleep cycle for most people")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let pending = naps.pendingNap {
                    pendingCard(pending)
                } else if let active = naps.activeNap {
                    activeCard(active)
                } else {
                    napCoachCard
                    presetCard
                    startButton
                }
                historyCard
                guidance
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Nap")
        .navigationBarTitleDisplayMode(.inline)
        // A one-second tick rather than a Timer publisher: this view only exists
        // while it's on screen, and TimelineView would redraw the whole card.
        // The tick only moves the progress ring. It never ended a nap, and
        // it does not exist while this screen is off, which is why ending a
        // nap is `NapStore.reconcile`'s job -- called here and on every
        // foreground activation in `RootView`.
        .task {
            naps.reconcile()
            while !Task.isCancelled {
                now = .now
                if naps.activeNap.map({ now > $0.targetEnd }) == true {
                    naps.reconcile(now: now)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Pending

    /// A nap whose target passed while Zoon was not running.
    ///
    /// Asking is the point. `finish()` used to record `end: .now` from a
    /// button, so opening the app hours after a twenty-minute nap and tapping
    /// stop logged a multi-hour nap into `SleepNeed.napCreditMinutes` and
    /// wiped out most of tonight's requirement -- from a duration nobody
    /// observed. Zoon offers the target as the conservative default and lets
    /// the user drop it entirely, because "I don't remember" is a real answer
    /// and a gap beats a guess.
    private func pendingCard(_ pending: NapStore.PendingNap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(Theme.text(15, weight: .semibold))
                    .foregroundStyle(Theme.Metric.strain)
                Text("Unfinished nap")
                    .font(Theme.label(15, weight: .semibold))
            }
            Text("You started a \(pending.targetMinutes)-minute nap at \(pending.start.formatted(date: .omitted, time: .shortened)), and Zoon wasn't running when it was due to end. It doesn't know when you actually woke up.")
                .font(Theme.text(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    naps.acceptPendingAtTarget()
                    Haptics.success()
                } label: {
                    Text("Log \(pending.targetMinutes) min")
                        .font(Theme.label(14, weight: .semibold))
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(Theme.Metric.strain.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    naps.discardPending()
                    Haptics.tap()
                } label: {
                    Text("Don't log it")
                        .font(Theme.label(14, weight: .semibold))
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(Theme.neutral(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Active

    private func activeCard(_ nap: NapStore.ActiveNap) -> some View {
        let elapsed = now.timeIntervalSince(nap.start)
        let target = Double(nap.targetMinutes * 60)
        let progress = min(1, elapsed / target)

        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.neutral(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [Theme.Metric.strain, Theme.Metric.sleep],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: 2) {
                    Text(formatted(max(0, target - elapsed)))
                        .font(Theme.numeral(38))
                        .monospacedDigit()
                    Text("remaining")
                        .font(Theme.label(11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)
            // The ring breathes only while a nap is actually running. A pulse
            // on static content trains people to ignore pulses.
            .breathing(true, tint: Theme.Metric.sleep)

            HStack(spacing: 12) {
                Button {
                    naps.cancel()
                } label: {
                    Text("Cancel")
                        .font(Theme.label(14, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Theme.neutral(0.09), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    naps.finish()
                    Haptics.success()
                } label: {
                    Label("I'm awake", systemImage: "sun.max.fill")
                        .font(Theme.label(14, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Theme.Metric.strain.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Nap Coach

    private var napCoachCard: some View {
        let tint: Color = switch recommendation.advice {
        case .recommended: Theme.Metric.recoveryHigh
        case .optional: Theme.Metric.sleep
        case .avoid: Theme.Metric.recoveryMid
        }
        let symbol: String = switch recommendation.advice {
        case .recommended: "checkmark.circle.fill"
        case .optional: "circle.dashed"
        case .avoid: "xmark.circle.fill"
        }
        let title: String = switch recommendation.advice {
        case .recommended(let minutes): "Nap recommended · ~\(minutes) min"
        case .optional: "Nap optional"
        case .avoid: "Skip the nap"
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(Theme.label(14, weight: .bold))
                Spacer()
                if recommendation.isRecommended {
                    Button {
                        if case .recommended(let minutes) = recommendation.advice {
                            selectedMinutes = minutes
                        }
                    } label: {
                        Text("Use this")
                            .font(Theme.label(11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(tint.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    // MARK: - Setup

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How long?", systemImage: "powersleep")

            ForEach(presets, id: \.minutes) { preset in
                Button {
                    selectedMinutes = preset.minutes
                } label: {
                    HStack(spacing: 12) {
                        Text("\(preset.minutes)")
                            .font(Theme.numeral(19))
                            .monospacedDigit()
                            .frame(width: 38)
                            .foregroundStyle(
                                selectedMinutes == preset.minutes ? Theme.Metric.strain : .secondary
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.label)
                                .font(Theme.label(14, weight: .semibold))
                            Text(preset.detail)
                                .font(Theme.text(10))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Image(systemName: selectedMinutes == preset.minutes
                              ? "largecircle.fill.circle" : "circle")
                            // Both branches must be the same type: `.tertiary`
                            // is a ShapeStyle, not a Color, so it can't unify
                            // with Theme.Metric.strain in a ternary.
                            .foregroundStyle(
                                selectedMinutes == preset.minutes
                                    ? Theme.Metric.strain
                                    : Theme.neutral(0.35)
                            )
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }

    private var startButton: some View {
        Button {
            naps.start(targetMinutes: selectedMinutes)
            Haptics.tap()
        } label: {
            Label("Start nap", systemImage: "play.fill")
                .font(Theme.label(16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [Theme.Metric.strain, Theme.Metric.sleep],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - History

    @ViewBuilder
    private var historyCard: some View {
        let recent = naps.recent(days: 7)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Recent naps",
                    subtitle: "Counted against tonight's sleep need.",
                    systemImage: "clock.arrow.circlepath"
                )
                ForEach(recent) { nap in
                    HStack {
                        Text(nap.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .font(Theme.label(12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(nap.minutes)) min")
                            .font(Theme.label(13, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            .glassCard()
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nap timing", systemImage: "lightbulb.fill")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.yellow)
            Text("""
                Naps after about 3pm eat into the sleep pressure you need for tonight. \
                If you're short on sleep and it's already evening, going to bed earlier \
                beats napping.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Nap") {
    NavigationStack { NapView() }
        .zoonPreviewEnvironment()
}
