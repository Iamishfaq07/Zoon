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
                coverageRow("Sleep duration", available: night.timeAsleepMinutes > 0)
                coverageRow("Sleep stages", available: night.hasStageBreakdown)
                coverageRow("Heart rate", available: night.avgHeartRate != nil)
                coverageRow("Resting heart rate", available: night.restingHeartRate != nil)
                coverageRow("HRV", available: night.avgHRV != nil)
                coverageRow("Respiratory rate", available: night.avgRespiratoryRate != nil)
                coverageRow("Blood oxygen", available: night.avgSpO2 != nil)
                coverageRow("Wrist temperature", available: night.wristTempDeltaC != nil)
                coverageRow("Breathing disturbances", available: night.breathingDisturbances != nil)

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
            Text("Unavailable data is excluded from scores rather than treated as average or zero.")
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

            Link(
                "Read the full privacy policy",
                destination: URL(string: "https://github.com/Iamishfaq07/Zoon/blob/main/PRIVACY.md")!
            )
        } header: {
            Text("Where data lives")
        } footer: {
            Text("Delete Everything removes SwiftData rows, preferences, naps, snore summaries, widget files, Watch context, AI cache, reminders, and live activities. HealthKit remains untouched.")
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
            Text("Apple does not reveal whether individual HealthKit read categories were denied. Coverage above shows what Zoon actually received without guessing about your permission choices.")
        }
    }

    private func coverageRow(_ label: String, available: Bool) -> some View {
        LabeledContent(label) {
            Label(
                available ? "Available" : "Missing",
                systemImage: available ? "checkmark.circle.fill" : "minus.circle"
            )
            .foregroundStyle(available ? Theme.Metric.recoveryHigh : Color.gray)
        }
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
