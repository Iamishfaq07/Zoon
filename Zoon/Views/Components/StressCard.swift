import SwiftUI

/// The one live number on a screen otherwise built from last night.
///
/// Positioned to read as a status line, not a headline — recovery is still
/// the verdict for the day; this is a same-day correction to it, the kind of
/// thing that says "you were recovered this morning, but today has been a lot".
///
/// Labeled "Physiological Load — Experimental" in the UI, not "Stress" --
/// the underlying `StressScore` type name is unchanged, but the user-facing
/// framing shouldn't imply a measurement of psychological stress this
/// signal was never built to make, and "Experimental" is honest about the
/// baseline mismatch `StressScore`'s own doc comment explains. See that
/// type's "Why Experimental" section for the full reasoning.
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

    /// True when today's elevated HR/HRV reading plausibly still reflects
    /// exercise rather than autonomic load.
    ///
    /// `StressScore` now excludes workouts, the minutes right after them,
    /// and unlogged high-movement hours before averaging (see
    /// `SleepDataCoordinator.refreshTodayStress`), which removes most of
    /// this -- but the exclusion is hour-grained and buffer-limited, so a
    /// day with a lot of exertion right at the edges of those windows can
    /// still leak through. When today's Strain says the day included real
    /// exertion, this says so as a caveat, rather than leaving an elevated
    /// reading to be read as pure autonomic load.
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
                Circle().stroke(Theme.neutral(0.10), lineWidth: 6)
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
                    Text("Load today")
                        .font(Theme.label(13, weight: .semibold))
                    StatusPill(text: "Experimental", tint: .secondary)
                    if stress.isEstimate {
                        StatusPill(text: "Estimate", tint: .secondary)
                    }
                }
                Text(mayReflectActivity ? "Today includes real exertion -- this may still reflect exercise, not autonomic load." : stress.band.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            MetricInfoButton(
                title: "Physiological Load — Experimental",
                symbol: "waveform.path.ecg",
                tint: tint,
                explanation: [
                    "Compares your heart rate and HRV so far today against your own rolling baseline -- a live, same-day reading rather than a look back at last night. Not a measure of psychological stress.",
                    "Workouts, the minutes right after them, and unlogged high-movement hours are excluded before averaging, so ordinary exertion doesn't read as elevated load. That exclusion is hour-grained, not perfect -- check today's Daily Load if this reads high and you know you've been active.",
                    "Marked Experimental because the baseline it compares against is built from overnight resting physiology, and even a genuinely calm waking hour doesn't sit on the same scale sleep does. Resolution is also limited by however much of the day has elapsed, which is why it's additionally shown as an estimate until there's enough baseline history."
                ]
            )
        }
        .glassCard()
        // Elapsed-day fraction as a subtitle rather than a clock — "so far
        // today" matters more than the exact minute count, and clock text
        // this small competes with the number for attention.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Physiological load today, experimental, \(stress.band.label), \(stress.percent) percent")
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
