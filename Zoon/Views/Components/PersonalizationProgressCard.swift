import SwiftUI

/// "Your app is learning what normal looks like for you" — honest cold-start
/// messaging instead of silently showing nothing (or worse, a fake-confident
/// number) before there's enough history to earn it.
///
/// Hides itself once every tracked feature has cleared its minimum, so this
/// doesn't linger as permanent clutter on an app someone's used for months.
struct PersonalizationProgressCard: View {

    let nightsTracked: Int
    let taggedNights: Int

    private var rows: [(label: String, current: Int, target: Int)] {
        [
            ("Sleep timing (Regularity)", nightsTracked, SleepRegularity.minimumNights),
            ("Recovery baseline", nightsTracked, RecoveryScore.minimumBaselineNights),
            ("Body Clock", nightsTracked, BodyClock.minimumNights),
            ("Cause Finder", taggedNights, JournalCorrelator.minimumMatchedPairs)
        ]
    }

    private var isFullyPersonalized: Bool {
        rows.allSatisfy { $0.current >= $0.target }
    }

    var body: some View {
        if !isFullyPersonalized {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Learning your sleep",
                    subtitle: "Your baseline is built from your own history, not other users.",
                    systemImage: "chart.line.uptrend.xyaxis.circle"
                )
                ForEach(rows, id: \.label) { row in
                    row_(row)
                }
            }
            .glassCard()
        }
    }

    private func row_(_ row: (label: String, current: Int, target: Int)) -> some View {
        let progress = min(1, Double(row.current) / Double(max(row.target, 1)))
        let done = row.current >= row.target
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(row.label)
                    .font(Theme.label(12, weight: .medium))
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.Metric.recoveryHigh)
                } else {
                    Text("\(row.current)/\(row.target) nights")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if !done {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(Theme.Metric.sleep).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

#Preview("Personalization Progress") {
    ScrollView {
        VStack(spacing: 16) {
            PersonalizationProgressCard(nightsTracked: 9, taggedNights: 3)
            PersonalizationProgressCard(nightsTracked: 30, taggedNights: 10)
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
