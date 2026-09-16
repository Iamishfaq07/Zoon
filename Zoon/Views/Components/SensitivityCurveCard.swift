import SwiftUI

/// One dose-response curve, drawn as the brief draws it: a band label, and one
/// line under it saying what that band looked like.
///
/// **Why bands rather than a plotted line.** The engine's reason is that a
/// smooth curve implies a resolution nobody has; the view's reason is that the
/// interesting content here is three words, not a shape. "Little observed
/// difference" and "uncertain" are the same *height* on any chart and mean
/// completely different things, and a reader scanning a line would take the
/// second for the first.
///
/// **The intervals are folded away, not dropped.** Several of these bands will
/// be built on five or six nights, and their intervals are correspondingly
/// wide. Hiding them entirely would leave the verdicts above looking more
/// certain than they are; putting them on first look would bury the three
/// words that answer the question.
struct SensitivityCurveCard: View {

    let curve: SensitivityCurve.Curve

    @State private var showsIntervals = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: curve.dose.behaviour,
                subtitle: "Against \(curve.outcome.noun), over \(curve.totalNights.pluralized("night")).",
                systemImage: "chart.bar.xaxis"
            )

            VStack(alignment: .leading, spacing: 10) {
                ForEach(curve.readings) { reading in
                    row(reading)
                    if reading.id != curve.readings.last?.id {
                        Rectangle().fill(Theme.cardStroke).frame(height: 1)
                    }
                }
            }

            // The intervals are the evidence behind every verdict above, and
            // they are numbers most readers do not want on first look. Folded
            // away rather than dropped: hiding them entirely would leave the
            // verdicts looking more certain than they are.
            if curve.readings.contains(where: { $0.intervalLower != nil }) {
                DisclosureGroup(isExpanded: $showsIntervals) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(curve.readings) { reading in
                            if let text = reading.intervalText(outcome: curve.outcome) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(reading.band.label)
                                        .font(Theme.evidence)
                                    Spacer(minLength: 8)
                                    Text(text)
                                        .font(Theme.evidence)
                                        .foregroundStyle(Theme.inkTertiary)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("How much these could move")
                        .font(Theme.label(13, weight: .semibold))
                }
                .onChange(of: showsIntervals) { _, _ in Haptics.select() }
            }

            Text(curve.caveat)
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func row(_ reading: SensitivityCurve.Reading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Label and night count sit together until the type is wide
            // enough that they cannot, then they stack rather than truncate.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(reading.band.label)
                        .font(Theme.label(14, weight: .semibold))
                    Spacer(minLength: 8)
                    nightCount(reading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.band.label)
                        .font(Theme.label(14, weight: .semibold))
                    nightCount(reading)
                }
            }

            Text(reading.sentence(outcome: curve.outcome))
                .font(Theme.text(14))
                .foregroundStyle(tint(reading.verdict))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.band.label)
        .accessibilityValue(
            "\(reading.sentence(outcome: curve.outcome)). \(reading.nights.pluralized("night"))."
        )
    }

    private func nightCount(_ reading: SensitivityCurve.Reading) -> some View {
        Text(reading.nights.pluralized("night"))
            .font(Theme.evidence)
            .foregroundStyle(Theme.inkTertiary)
            .monospacedDigit()
    }

    /// An association is the only thing coloured. "Uncertain" and "little
    /// observed difference" are both findings, and tinting them would turn a
    /// statement about evidence into a verdict about the behaviour.
    private func tint(_ verdict: SensitivityCurve.Verdict) -> Color {
        if case .associated = verdict { return Theme.Metric.recoveryMid }
        return Theme.inkSecondary
    }
}

/// The dimensions §22 asks for that cannot be built from what Zoon stores.
///
/// Shown next to the curves rather than left out. A feature that silently
/// covers three of six things it was asked about reads as broken; one that
/// says which three and why reads as honest, and tells the reader what would
/// have to change.
struct SensitivityGapsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "What Zoon cannot chart yet",
                subtitle: "Asked for, but not stored in a form that would support it.",
                systemImage: "questionmark.circle"
            )
            ForEach(SensitivityCurve.unavailable) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.behaviour)
                        .font(Theme.label(13, weight: .semibold))
                    Text(entry.reason)
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
    }
}
