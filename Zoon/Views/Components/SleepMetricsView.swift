import SwiftUI

/// Actual sleep against sleep need, as two bars on one scale.
///
/// Both bars are drawn against the *same* maximum, so their lengths are
/// directly comparable and the gap between them is the shortfall you can see
/// without doing arithmetic. Scaling each bar to its own value — the obvious
/// implementation, and what a naive "percentage-width" reading of the design
/// gives — would draw a short night and a long need as two identical full
/// bars, which is precisely the comparison this exists to make.
struct SleepMetricsView: View {

    let actualMinutes: Double
    let needMinutes: Double
    /// Naps already counted into `actualMinutes`, shown so the total is
    /// explicable when it does not match last night alone.
    var napMinutes: Double = 0

    private var scale: Double { max(actualMinutes, needMinutes, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            bar(
                label: "Actual sleep",
                minutes: actualMinutes,
                tint: Theme.Family.sleep,
                footnote: napMinutes >= 1
                    ? "includes \(Int(napMinutes.rounded()))m of naps"
                    : nil
            )
            bar(
                label: "Sleep need",
                minutes: needMinutes,
                tint: Theme.Family.attention,
                footnote: nil
            )
        }
        .glassCard()
    }

    private func bar(label: String, minutes: Double, tint: Color, footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.label(13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                Text(SleepNightFeatures.formatMinutes(minutes))
                    .font(Theme.label(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.neutral(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.75), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(minutes / scale)))
                }
            }
            .frame(height: 8)

            if let footnote {
                Text(footnote)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(SleepNightFeatures.formatMinutes(minutes))
    }
}

#Preview("Sleep balance") {
    ZStack {
        Theme.background.ignoresSafeArea()
        SleepMetricsView(actualMinutes: 370, needMinutes: 588, napMinutes: 25)
            .padding()
    }
    .zoonPreviewEnvironment()
}
