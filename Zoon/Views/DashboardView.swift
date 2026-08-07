import SwiftUI
import UIKit

/// Home screen: last night at a glance.
struct DashboardView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zoon")
            .refreshable {
                await coordinator.refresh()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.state {
        case .idle, .loading:
            LoadingState()

        case let .loaded(features, insight), let .mock(features, insight):
            nightContent(features: features, insight: insight)

        case let .empty(reason):
            EmptyState(reason: reason) {
                Task { await coordinator.refresh() }
            }

        case let .failed(message):
            ErrorState(message: message) {
                Task { await coordinator.refresh() }
            }
        }
    }

    private func nightContent(features: SleepNightFeatures, insight: SleepInsight) -> some View {
        VStack(spacing: ZoonStyle.stackSpacing) {
            SleepSummaryCard(
                features: features,
                score: SleepScore.compute(for: features, goalMinutes: preferences.sleepGoalMinutes),
                goalMinutes: preferences.sleepGoalMinutes
            )

            InsightCard(insight: insight, engineName: insight.source.displayName)

            StageBreakdownCard(features: features)

            if features.sleepDebtMinutes14Day != nil {
                SleepDebtCard(features: features, goalMinutes: preferences.sleepGoalMinutes)
            }

            VitalsCard(features: features)

            footer(features: features)
        }
    }

    private func footer(features: SleepNightFeatures) -> some View {
        VStack(spacing: 4) {
            if let source = features.sourceName {
                Text("Source: \(source)")
            }
            if let last = coordinator.lastRefresh {
                Text("Updated \(last, format: .dateTime.hour().minute())")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - States

private struct LoadingState: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Reading last night…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// Shown when queries succeeded but found nothing.
///
/// This screen exists because the failure mode it replaces — an eternal spinner —
/// is indistinguishable from a hang, and HealthKit gives us no way to tell the
/// user "you denied permission". So it names both plausible causes and gives a
/// direct route to Settings.
private struct EmptyState: View {

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
                    // Deep link to this app's page in Settings, where the Health
                    // permission toggles live.
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

private struct ErrorState: View {
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

// MARK: - Supporting cards

/// Sleep debt with a "bank balance" framing, matching the widget.
struct SleepDebtCard: View {

    let features: SleepNightFeatures
    let goalMinutes: Double

    private var debt: Double { features.sleepDebtMinutes14Day ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Sleep Debt", systemImage: "banknote")
                    .font(.headline)
                Spacer()
                Text(debt < 15 ? "Even" : "−\(SleepNightFeatures.formatMinutes(debt))")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(debt < 15 ? .green : .orange)
            }

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zoonCard()
    }

    private var explanation: String {
        if debt < 15 {
            return "You're square with your \(SleepNightFeatures.formatMinutes(goalMinutes)) goal over the last two weeks. Nice."
        }
        return """
            Total shortfall against your \(SleepNightFeatures.formatMinutes(goalMinutes)) goal over 14 nights. \
            Extra weekend sleep doesn't cancel it out — going to bed earlier does.
            """
    }
}

/// Overnight physiology. Every row is optional: not every watch measures every
/// signal, and a row of dashes teaches the user nothing.
struct VitalsCard: View {

    let features: SleepNightFeatures

    private var rows: [(String, String, String)] {
        var result: [(String, String, String)] = []
        if let hr = features.avgHeartRate {
            result.append(("heart", "Average heart rate", "\(Int(hr)) bpm"))
        }
        if let resp = features.avgRespiratoryRate {
            result.append(("lungs", "Respiratory rate", String(format: "%.1f /min", resp)))
        }
        if let spo2 = features.avgSpO2 {
            result.append(("drop", "Blood oxygen", String(format: "%.0f%%", spo2)))
        }
        if let temp = features.wristTempDeltaC {
            result.append(("thermometer.medium", "Wrist temp", String(format: "%+.1f°C", temp)))
        }
        return result
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overnight Vitals")
                    .font(.headline)

                ForEach(rows, id: \.1) { symbol, label, value in
                    HStack {
                        Label(label, systemImage: symbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(value)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                }

                Text(SleepInsight.disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .zoonCard()
        }
    }
}

// MARK: - Previews

#Preview("Dashboard") {
    DashboardView()
        .zoonPreviewEnvironment()
}

#Preview("Sleep debt card") {
    ScrollView {
        VStack(spacing: 16) {
            SleepDebtCard(features: MockData.poorNight, goalMinutes: 480)
            SleepDebtCard(features: MockData.goodNight, goalMinutes: 420)
            VitalsCard(features: MockData.goodNight)
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
