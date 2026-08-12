import SwiftUI

/// The one live number on a screen otherwise built from last night.
///
/// Positioned to read as a status line, not a headline — recovery is still
/// the verdict for the day; this is a same-day correction to it, the kind of
/// thing that says "you were recovered this morning, but today has been a lot".
struct StressCard: View {

    let stress: StressScore
    /// Today's Strain value (0...21), when available -- used only to decide
    /// whether to show the activity caveat below. See that property's doc
    /// comment for why this card needs it at all.
    var todayStrain: Double?

    /// Above this, today plausibly includes real exercise rather than just
    /// ordinary daily movement -- same threshold `SleepNeed` uses for "this
    /// was a hard enough day to raise tonight's requirement."
    private static let meaningfulActivityThreshold = 8.0

    /// True when today's elevated HR/HRV reading plausibly reflects exercise
    /// rather than psychological load.
    ///
    /// `StressScore` averages heart rate and HRV across the whole elapsed
    /// day against an *overnight* baseline, with no filtering for activity --
    /// a run or a hard gym session reads exactly like autonomic stress to
    /// this math, because physiologically an elevated heart rate looks the
    /// same either way. Excluding active periods from the average would be
    /// the more correct fix, but isn't implemented; this is the honest
    /// stopgap the card can offer today: when Strain says the day included
    /// real exertion, say so, rather than leaving an elevated reading to be
    /// read as pure psychological stress.
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
                Text(mayReflectActivity ? "Today includes real exertion -- this may reflect exercise, not stress." : stress.band.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            MetricInfoButton(
                title: "Stress Today",
                symbol: "waveform.path.ecg",
                tint: tint,
                explanation: [
                    "Compares your heart rate and HRV so far today against your own rolling baseline -- a live, same-day reading rather than a look back at last night.",
                    "This averages the whole elapsed day without separating out exercise: a run or a hard workout raises heart rate the same way psychological stress does, physiologically, so an elevated reading on an active day often reflects exertion rather than autonomic load. Check today's Daily Load if this reads high and you know you've been active.",
                    "Resolution is limited by however much of the day has elapsed: an early reading is a smaller sample than one taken in the evening, which is why it's shown as an estimate until there's enough baseline history."
                ]
            )
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
        StressCard(
            stress: StressScore(percent: 72, band: .high, sampledMinutes: 500, avgHeartRate: 84, avgHRV: 33, isEstimate: false),
            todayStrain: 14
        )
    }
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}
