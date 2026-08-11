import SwiftUI

/// Select-sections-then-export screen for the clinician PDF.
struct ClinicianReportView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    @State private var rangeDays = 30
    @State private var selectedSections = Set(ClinicianReportGenerator.Section.allCases)
    @State private var reportURL: URL?
    @State private var errorMessage: String?

    private let rangeOptions = [30, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                header
                rangeCard
                sectionsCard
                generateButton
                if let reportURL {
                    ShareLink(item: reportURL) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share report")
                        }
                        .font(Theme.label(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.Metric.recoveryHigh.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                disclaimerCard
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Clinician Report")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't generate report", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        Text("A PDF summary of your sleep data, formatted for a clinician to skim -- light background, print-friendly, generated entirely on this device.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rangeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Range", systemImage: "calendar")
            Picker("Range", selection: $rangeDays) {
                ForEach(rangeOptions, id: \.self) { Text("\($0) days").tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .glassCard()
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sections to include", systemImage: "checklist")
            ForEach(ClinicianReportGenerator.Section.allCases) { section in
                Button {
                    if selectedSections.contains(section) {
                        selectedSections.remove(section)
                    } else {
                        selectedSections.insert(section)
                    }
                } label: {
                    HStack {
                        Image(systemName: selectedSections.contains(section) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedSections.contains(section) ? Theme.Metric.sleep : .secondary)
                        Text(section.rawValue)
                            .font(Theme.label(13))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }

    private var generateButton: some View {
        Button {
            generate()
        } label: {
            Text("Generate Report")
                .font(Theme.label(15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Theme.Metric.sleep, Theme.Metric.battery], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .disabled(selectedSections.isEmpty)
        .opacity(selectedSections.isEmpty ? 0.5 : 1)
    }

    private var disclaimerCard: some View {
        Text("""
            This report contains measurements and estimates from a consumer wearable device \
            and is intended to support discussion with a qualified healthcare professional. \
            It is not a diagnosis.
            """)
            .font(Theme.text(10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func generate() {
        let data = ClinicianReportGenerator.generate(
            nights: coordinator.recentNights,
            sections: selectedSections,
            rangeDays: rangeDays,
            goalMinutes: preferences.sleepGoalMinutes
        )
        do {
            reportURL = try DataExporter.writeTemporary(
                data, filename: ClinicianReportGenerator.filename(rangeDays: rangeDays)
            )
            Haptics.success()
        } catch {
            errorMessage = "Couldn't write the report file: \(error.localizedDescription)"
        }
    }
}

#Preview("Clinician Report") {
    NavigationStack { ClinicianReportView() }
        .zoonPreviewEnvironment()
}
