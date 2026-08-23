import SwiftUI

/// A slow-moving read on how sleep has actually been going -- distinct from
/// Recovery or Sleep Intelligence, which both reset every morning. See
/// `SleepHealth`'s own doc comment for why this exists as a separate metric
/// rather than another nightly score.
struct SleepHealthView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    @State private var window: SleepHealth.Window = .month

    private var health: SleepHealth {
        let checkIns = coordinator.journal.allEntries().map {
            SleepHealth.DatedMorningCheckIn(date: $0.date, feeling: $0.feeling?.rawValue)
        }
        return SleepHealth.compute(
            window: window,
            goalMinutes: preferences.sleepGoalMinutes,
            nights: coordinator.recentNights,
            morningCheckIns: checkIns,
            obligationWeekdays: preferences.obligationWeekdays
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                windowPicker
                hero
                if !health.components.isEmpty {
                    componentsCard
                }
                explanationCard
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Sleep Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var windowPicker: some View {
        Picker("", selection: $window) {
            ForEach(SleepHealth.Window.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text("Sleep Health -- \(window.label.lowercased())")
                .font(Theme.label(13))
                .foregroundStyle(.secondary)
            if let score = health.score {
                Text(String(format: "%.0f", score))
                    .font(Theme.numeral(46))
                    .monospacedDigit()
                if let band = health.band {
                    StatusPill(text: band.label, tint: Theme.Metric.recoveryHigh)
                }
            } else {
                Text("--")
                    .font(Theme.numeral(46))
                    .foregroundStyle(.tertiary)
                StatusPill(text: "Insufficient data", tint: .secondary)
            }
            Text("Built from \(health.nightCount) night\(health.nightCount == 1 ? "" : "s") in this window. \(health.confidence.label).")
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var componentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What it's built from", systemImage: "list.bullet.rectangle")
            ForEach(health.components) { component in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(component.label)
                            .font(Theme.label(12))
                        Spacer()
                        Text(String(format: "%.0f", component.score))
                            .font(Theme.label(13, weight: .semibold))
                            .monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.neutral(0.08))
                            Capsule()
                                .fill(Theme.Metric.recoveryHigh)
                                .frame(width: geo.size.width * component.score / 100)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .glassCard()
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How this is measured", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                A slower-moving picture than any single night: sufficiency, regularity, continuity and \
                estimated sleep debt every time, plus breathing stability and self-reported restfulness \
                when there's enough data behind them. Components with nothing real to measure are left out \
                rather than guessed at, so the score you see is only ever built from what Zoon actually knows.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Sleep Health") {
    NavigationStack { SleepHealthView() }
        .zoonPreviewEnvironment()
}
