import SwiftUI

/// The COVERAGE MATRIX visual grammar: which signals the last seven nights
/// actually carried, as a grid of marks -- filled for present, outlined for
/// missing. Answers "can Zoon trust my data?" in one glance and gives every
/// cell a spoken label.
///
/// Presence is read straight off `SleepNightFeatures`' optionals, the same
/// fields every score checks before including a signal. No new statistic:
/// a night either had `avgHRV` or it didn't.
struct ZoonCoverageMatrix: View {
    let nights: [SleepNightFeatures]

    private struct Row: Identifiable {
        let id: String
        let label: String
        let tint: Color
        let present: (SleepNightFeatures) -> Bool
    }

    private var rows: [Row] {
        [
            Row(id: "sleep", label: "Sleep", tint: Theme.Family.sleep) { _ in true },
            Row(id: "stages", label: "Stages", tint: Theme.Family.sleep) { $0.hasStageBreakdown },
            Row(id: "hr", label: "Heart rate", tint: Theme.Metric.heart) { $0.avgHeartRate != nil },
            Row(id: "hrv", label: "HRV", tint: Theme.Metric.hrv) { $0.avgHRV != nil },
            Row(id: "resp", label: "Breathing", tint: Theme.Family.breathing) { $0.avgRespiratoryRate != nil },
            Row(id: "spo2", label: "Blood oxygen", tint: Theme.Family.breathing) { $0.avgSpO2 != nil },
            Row(id: "temp", label: "Temperature", tint: Theme.Family.circadian) { $0.wristTempDeltaC != nil }
        ]
    }

    private var recent: [SleepNightFeatures] {
        Array(nights.sorted { $0.date < $1.date }.suffix(7))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZoonSectionHeader("Last 7 nights") {
                Text("● recorded  ○ missing")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
            }

            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 10) {
                GridRow {
                    Color.clear.frame(width: 96, height: 1)
                    ForEach(recent) { night in
                        Text(night.date, format: .dateTime.weekday(.narrow))
                            .font(Theme.text(10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label)
                            .font(Theme.text(12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                        ForEach(recent) { night in
                            let present = row.present(night)
                            Circle()
                                .strokeBorder(row.tint.opacity(present ? 0 : 0.45), lineWidth: 1.2)
                                .background(Circle().fill(present ? row.tint.opacity(0.9) : .clear))
                                .frame(width: 10, height: 10)
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(row.label), \(night.date.formatted(.dateTime.weekday(.wide))), \(present ? "recorded" : "missing")")
                        }
                    }
                }
            }

            Text(summary)
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: String {
        guard !recent.isEmpty else { return "No nights recorded yet." }
        let gaps = rows.dropFirst().filter { row in recent.contains { !row.present($0) } }
        if gaps.isEmpty { return "Every signal was recorded on every night. Scores used the full model." }
        let names = gaps.map { $0.label.lowercased() }.joined(separator: ", ")
        return "Missing on some nights: \(names). A missing signal is left out of that night's score, never assumed."
    }
}

#Preview("Coverage matrix") {
    ScrollView {
        ZoonCoverageMatrix(nights: MockData.history)
            .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
