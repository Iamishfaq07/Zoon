import SwiftUI

/// The four recovery signals as readings, not just as colours.
///
/// The ring's legend named the signals; it never said what any of them
/// actually measured. "HRV" tells you nothing you did not already know —
/// "HRV 81 ms, optimal" is the sentence people want, and every part of it was
/// already computed and thrown away.
///
/// The qualifier comes from the same `normalized` value the ring plots, so
/// the word and the arc can never disagree. An unmeasured signal says so
/// rather than scoring.
struct ScoreDrivers: View {

    let components: [RecoveryScore.Component]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score drivers")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSecondary)

            HStack(alignment: .top, spacing: 0) {
                ForEach(components) { component in
                    VStack(spacing: 3) {
                        Image(systemName: Self.symbol(for: component.label))
                            .font(Theme.text(15, weight: .semibold))
                            .foregroundStyle(Self.tint(for: component.label))

                        Text(Self.shortLabel(for: component.label))
                            .font(Theme.label(11, weight: .semibold))

                        Text(component.isAvailable ? component.detail : "—")
                            .font(Theme.label(12, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(Self.qualifier(for: component))
                            .font(Theme.text(11))
                            .foregroundStyle(Self.qualifierColor(for: component))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        component.isAvailable
                            ? "\(component.label), \(component.detail), \(Self.qualifier(for: component))"
                            : "\(component.label), not measured"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One scale for all four, from the value the ring already plots, so the
    /// word under a signal and the length of its axis are the same fact.
    private static func qualifier(for component: RecoveryScore.Component) -> String {
        guard component.isAvailable else { return "Not measured" }
        return switch component.normalized {
        case ..<0.35: "Low"
        case ..<0.55: "Fair"
        case ..<0.78: "Good"
        default: "Optimal"
        }
    }

    private static func qualifierColor(for component: RecoveryScore.Component) -> Color {
        guard component.isAvailable else { return Theme.inkTertiary }
        return switch component.normalized {
        case ..<0.35: Theme.Family.deviation
        case ..<0.55: Theme.Family.attention
        default: Theme.Family.recovery
        }
    }

    private static func tint(for label: String) -> Color {
        switch label {
        case "HRV": Theme.Family.recovery
        case "Resting HR": Theme.Family.bodySignals
        case "Sleep": Theme.Family.sleep
        default: Theme.Family.breathing
        }
    }

    private static func symbol(for label: String) -> String {
        switch label {
        case "HRV": "waveform.path.ecg"
        case "Resting HR": "heart.fill"
        case "Sleep": "moon.fill"
        default: "lungs.fill"
        }
    }

    private static func shortLabel(for label: String) -> String {
        switch label {
        case "Resting HR": "RHR"
        case "Respiratory": "Resp"
        default: label
        }
    }
}
