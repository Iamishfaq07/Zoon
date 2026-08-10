import SwiftUI

/// The one live number on a screen otherwise built from last night.
///
/// Positioned to read as a status line, not a headline — recovery is still
/// the verdict for the day; this is a same-day correction to it, the kind of
/// thing that says "you were recovered this morning, but today has been a lot".
struct StressCard: View {

    let stress: StressScore

    private var tint: Color {
        switch stress.band {
        case .calm: Theme.Metric.recoveryHigh
        case .elevated: Theme.Metric.recoveryMid
        case .high: Theme.Metric.recoveryLow
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: Double(stress.percent) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(stress.percent)")
                    .font(Theme.numeral(15))
                    .monospacedDigit()
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Stress today")
                        .font(Theme.label(13, weight: .semibold))
                    if stress.isEstimate {
                        StatusPill(text: "Estimate", tint: .secondary)
                    }
                }
                Text(stress.band.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .glassCard()
        // Elapsed-day fraction as a subtitle rather than a clock — "so far
        // today" matters more than the exact minute count, and clock text
        // this small competes with the number for attention.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stress today, \(stress.band.label), \(stress.percent) percent")
    }
}

#Preview("Stress") {
    VStack(spacing: 12) {
        StressCard(stress: StressScore(percent: 28, band: .calm, sampledMinutes: 200, avgHeartRate: 64, avgHRV: 58, isEstimate: false))
        StressCard(stress: StressScore(percent: 58, band: .elevated, sampledMinutes: 400, avgHeartRate: 76, avgHRV: 41, isEstimate: false))
        StressCard(stress: StressScore(percent: 84, band: .high, sampledMinutes: 600, avgHeartRate: 88, avgHRV: 29, isEstimate: true))
    }
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}
