import SwiftUI

/// Nap timer and log.
///
/// Naps matter to this app specifically because they feed `SleepNeed` — a
/// 25-minute nap genuinely reduces tonight's requirement, and a model that
/// ignored them would overstate your debt. HealthKit's own sleep records don't
/// reliably capture short daytime naps, so logging one here fills a real gap.
struct NapView: View {

    @Environment(NapStore.self) private var naps

    @State private var selectedMinutes: Int = 20
    @State private var now: Date = .now

    /// Nap lengths that correspond to actual sleep architecture rather than
    /// round numbers: 20 stays above deep sleep and avoids grogginess, 90 is a
    /// full cycle so you wake at the light end of one.
    private let presets: [(minutes: Int, label: String, detail: String)] = [
        (10, "Power", "Alertness boost, no grogginess"),
        (20, "Classic", "The safest length — stays out of deep sleep"),
        (30, "Long", "Some grogginess likely on waking"),
        (90, "Full cycle", "A complete cycle, wakes you at the light end")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let active = naps.activeNap {
                    activeCard(active)
                } else {
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
        .task {
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Active

    private func activeCard(_ nap: NapStore.ActiveNap) -> some View {
        let elapsed = now.timeIntervalSince(nap.start)
        let target = Double(nap.targetMinutes * 60)
        let progress = min(1, elapsed / target)

        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 14)
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
                        .background(Color.white.opacity(0.09), in: Capsule())
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
                                    : Color.white.opacity(0.35)
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
        .environment(NapStore.preview)
        .preferredColorScheme(.dark)
}
