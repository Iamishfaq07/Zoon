import SwiftUI

/// Every stored night, browsable — the piece that was missing between "today"
/// and the aggregate charts on Trends. Today's card, the Sleep tab, and
/// `SleepDetailView` were all hard-wired to `coordinator.state.context`, which
/// only ever holds the most recent night; there was no way to open any other
/// one even though every night is already sitting in `recentNights`.
struct NightHistoryView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var nights: [SleepNightFeatures] {
        coordinator.recentNights.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(nights) { night in
                    NavigationLink {
                        PastNightDetailView(night: night)
                    } label: {
                        row(for: night)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
            .padding(.top, 4)
        }
        .nightBackground()
        .navigationTitle("Past Nights")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if nights.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded yet",
                    systemImage: "moon.zzz",
                    description: Text("Nights appear here once Zoon has read them from Health.")
                )
            }
        }
    }

    private func row(for night: SleepNightFeatures) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                Text(night.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(Theme.label(14, weight: .semibold))
                Text("\(Int(night.sleepEfficiencyPercent))% efficiency · \(night.wakeCount) awakenings")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(night.formattedTimeAsleep)
                .font(Theme.label(15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.Metric.sleep)

            Image(systemName: "chevron.right")
                .font(Theme.text(12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassCard()
    }
}

#Preview("Night History") {
    NavigationStack { NightHistoryView() }
        .zoonPreviewEnvironment()
}
