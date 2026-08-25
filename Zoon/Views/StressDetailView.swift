import SwiftUI

/// Physiological Load's full working -- today's heart rate and HRV each
/// measured against their own rolling baseline, not just the blended
/// percent `StressCard` shows on Today.
struct StressDetailView: View {
    let stress: StressScore
    var todayStrain: Double?

    private static let meaningfulActivityThreshold = 8.0

    /// Same reasoning as `StressCard`'s own property -- see its doc comment.
    private var mayReflectActivity: Bool {
        stress.band != .calm && (todayStrain ?? 0) >= Self.meaningfulActivityThreshold
    }

    private var tint: Color {
        switch stress.band {
        case .calm: Theme.Metric.recoveryHigh
        case .elevated: Theme.Metric.recoveryMid
        case .high: Theme.Metric.recoveryLow
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                headerCard
                breakdownCard
                explanationCard
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Physiological Load")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.neutral(0.10), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(stress.percent) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(stress.percent)")
                        .font(Theme.numeral(30))
                        .monospacedDigit()
                    Text(stress.band.label)
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            HStack(spacing: 6) {
                StatusPill(text: "Experimental", tint: .secondary)
                if stress.isEstimate {
                    StatusPill(text: "Estimate", tint: .secondary)
                }
            }

            Text(mayReflectActivity ? "Today includes real exertion -- this may still reflect exercise, not autonomic load." : stress.band.detail)
                .font(Theme.text(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "What's driving it",
                subtitle: "Each signal measured against your own rolling baseline, so far today.",
                systemImage: "waveform.path.ecg"
            )

            component(
                label: "Heart Rate", symbol: "heart.fill",
                today: stress.avgHeartRate, baseline: stress.hrBaseline,
                unit: "bpm", higherIsMoreStressed: true
            )
            component(
                label: "HRV", symbol: "waveform.path.ecg.rectangle",
                today: stress.avgHRV, baseline: stress.hrvBaseline,
                unit: "ms", higherIsMoreStressed: false
            )

            Divider().overlay(Theme.cardStroke)

            Text("\(Int(stress.sampledMinutes)) minutes sampled so far today.")
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }

    /// One signal's row: today's reading, the baseline it's measured
    /// against, and the deviation between them. `higherIsMoreStressed`
    /// flips which direction counts as "more stressed" -- HR reads that way
    /// rising, HRV reads it falling, matching `StressScore.compute`'s own
    /// two component calculations.
    private func component(
        label: String, symbol: String,
        today: Double?, baseline: Double?,
        unit: String, higherIsMoreStressed: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(Theme.text(13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(label)
                .font(Theme.label(12, weight: .medium))
                .frame(width: 72, alignment: .leading)

            if let today, let baseline, baseline > 0 {
                let deviation = (today - baseline) / baseline
                let stressedDirection = higherIsMoreStressed ? deviation > 0 : deviation < 0

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(String(format: "%.0f", today)) \(unit) today")
                        .font(Theme.text(11))
                        .foregroundStyle(.primary)
                    Text("usual \(String(format: "%.0f", baseline)) \(unit)")
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                Text(String(format: "%+.0f%%", deviation * 100))
                    .font(Theme.text(11, weight: .semibold))
                    .foregroundStyle(stressedDirection ? Theme.Metric.recoveryMid : Theme.Metric.recoveryHigh)
                    .monospacedDigit()
            } else {
                Text("Not available")
                    .font(Theme.text(11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
            }
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compares your heart rate and HRV so far today against your own rolling baseline -- a live, same-day reading rather than a look back at last night. Not a measure of psychological stress.")
            Text("Workouts, the minutes right after them, and unlogged high-movement hours are excluded before averaging, so ordinary exertion doesn't read as elevated load. That exclusion is hour-grained, not perfect -- check today's Daily Load if this reads high and you know you've been active.")
            Text("Marked Experimental because the baseline it compares against is built from overnight resting physiology, and even a genuinely calm waking hour doesn't sit on the same scale sleep does. Resolution is also limited by however much of the day has elapsed, which is why it's additionally shown as an estimate until there's enough baseline history.")
        }
        .font(Theme.text(12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .glassCard()
    }
}

#Preview("Stress Detail") {
    NavigationStack {
        StressDetailView(
            stress: StressScore(
                percent: 72, band: .high, sampledMinutes: 480,
                avgHeartRate: 78, avgHRV: 34, hrBaseline: 64, hrvBaseline: 52,
                isEstimate: false
            ),
            todayStrain: 14
        )
    }
    .zoonPreviewEnvironment()
}

#Preview("Stress Detail — calm, no baseline yet") {
    NavigationStack {
        StressDetailView(
            stress: StressScore(
                percent: 28, band: .calm, sampledMinutes: 120,
                avgHeartRate: 62, avgHRV: nil, hrBaseline: 60, hrvBaseline: nil,
                isEstimate: true
            )
        )
    }
    .zoonPreviewEnvironment()
}
