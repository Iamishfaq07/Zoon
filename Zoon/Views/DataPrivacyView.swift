import SwiftUI
import UIKit

/// One place to understand freshness, sensor coverage, storage, permissions,
/// and erasure. Health guidance is only trustworthy when missing data is as
/// visible as present data.
struct DataPrivacyView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(NapStore.self) private var naps

    private var latest: SleepNightFeatures? { coordinator.recentNights.last }

    var body: some View {
        List {
            freshnessSection
            coverageSection
            storageSection
            permissionsSection
        }
        .scrollContentBackground(.hidden)
        .nightBackground()
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var freshnessSection: some View {
        Section("Freshness") {
            if let lastRefresh = coordinator.lastRefresh {
                LabeledContent("Last updated") {
                    Text(lastRefresh, format: .relative(presentation: .named))
                }
                LabeledContent("Status", value: freshnessLabel(since: lastRefresh))
            } else {
                LabeledContent("Status", value: "Not refreshed yet")
            }

            Button("Refresh from Health") {
                Task { await coordinator.refresh() }
            }
        }
    }

    @ViewBuilder
    private var coverageSection: some View {
        Section {
            if let night = latest {
                coverageGrid(Self.coverage(of: night))

                if let source = night.sourceName {
                    LabeledContent("Sleep source", value: source)
                }
            } else {
                ContentUnavailableView(
                    "No night to inspect",
                    systemImage: "waveform.path.ecg",
                    description: Text("Refresh after wearing your Watch to bed to see sensor coverage.")
                )
            }
        } header: {
            Text("Last-night coverage")
        } footer: {
            Text("Missing data is left out of scores, never filled in.")
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Processing", value: "On this device")
            LabeledContent("Network account", value: "None")
            LabeledContent("Nights stored", value: "\(coordinator.recentNights.count)")
            LabeledContent("Journal entries", value: "\(coordinator.journal.allEntries().count)")
            LabeledContent("Naps stored", value: "\(naps.naps.count)")
            LabeledContent("Widget sharing") {
                Text(AppGroup.isConfigured ? "App Group" : "Sample only")
            }
            LabeledContent("Health originals", value: "Never modified")

            if let privacyURL = URL(string: "https://github.com/Iamishfaq07/Zoon/blob/main/PRIVACY.md") {
                Link("Read the full privacy policy", destination: privacyURL)
            }
        } header: {
            Text("Where data lives")
        } footer: {
            Text("No account, no server. Health stays as recorded.")
        }
    }

    private var permissionsSection: some View {
        Section {
            Button("Open Zoon Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("iOS doesn't say what was denied, so coverage above shows what arrived.")
        }
    }

    private struct Signal: Identifiable {
        let label: String
        let symbol: String
        let available: Bool
        var id: String { label }
    }

    private static func coverage(of night: SleepNightFeatures) -> [Signal] {
        [
            Signal(label: "Duration", symbol: "bed.double.fill", available: night.timeAsleepMinutes > 0),
            Signal(label: "Stages", symbol: "chart.bar.fill", available: night.hasStageBreakdown),
            Signal(label: "Heart rate", symbol: "heart.fill", available: night.avgHeartRate != nil),
            Signal(label: "Resting HR", symbol: "heart.text.square.fill", available: night.restingHeartRate != nil),
            Signal(label: "HRV", symbol: "waveform.path.ecg", available: night.avgHRV != nil),
            Signal(label: "Breathing rate", symbol: "lungs.fill", available: night.avgRespiratoryRate != nil),
            Signal(label: "Blood oxygen", symbol: "drop.fill", available: night.avgSpO2 != nil),
            Signal(label: "Wrist temp", symbol: "thermometer.medium", available: night.wristTempDeltaC != nil),
            Signal(label: "Disturbances", symbol: "wind", available: night.breathingDisturbances != nil),
        ]
    }

    /// Last night's signals as tiles, lit when they arrived. Nine rows of
    /// "Available" / "Missing" said the same thing as one grid you can
    /// take in at once.
    private func coverageGrid(_ signals: [Signal]) -> some View {
        let arrived = signals.filter(\.available).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(arrived)")
                    .font(Theme.heading(24))
                    .monospacedDigit()
                Text("of \(signals.count) arrived")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(signals) { signal in
                    VStack(spacing: 6) {
                        Image(systemName: signal.available ? signal.symbol : "minus")
                            .font(Theme.text(16, weight: .semibold))
                            .foregroundStyle(signal.available ? Theme.Metric.recoveryHigh : Theme.inkTertiary)
                            .frame(height: 20)
                        Text(signal.label)
                            .font(Theme.text(11, weight: .medium))
                            .foregroundStyle(signal.available ? Theme.ink : Theme.inkTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(signal.available ? Theme.Metric.recoveryHigh.opacity(0.10) : Theme.neutral(0.04))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(signal.label): \(signal.available ? "arrived" : "missing")")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func freshnessLabel(since date: Date) -> String {
        let age = Date.now.timeIntervalSince(date)
        return switch age {
        case ..<3_600: "Current"
        case ..<21_600: "A few hours old"
        default: "Stale — refresh recommended"
        }
    }
}

#Preview("Data & Privacy") {
    NavigationStack { DataPrivacyView() }
        .zoonPreviewEnvironment()
}
