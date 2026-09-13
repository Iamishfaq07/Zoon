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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score drivers")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(components) { component in
                        row(for: component)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(components) { component in
                        column(for: component)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Four abreast, the way the mockup reads: the signal's mark to the left
    /// of its own small block of text, not stacked over it. Stacked, the
    /// glyph reads as a bullet for the column; beside the text it reads as
    /// belonging to that signal, which is what it is.
    private func column(for component: RecoveryScore.Component) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: Self.symbol(for: component.label))
                .font(Theme.text(15, weight: .semibold))
                .foregroundStyle(Self.tint(for: component.label))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)

            VStack(alignment: .leading, spacing: 1) {
                Text(Self.shortLabel(for: component.label))
                    .font(Theme.label(11, weight: .semibold))

                Text(component.isAvailable ? component.detail : "—")
                    .font(Theme.label(12, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("(\(Self.qualifier(for: component)))")
                    .font(Theme.text(11))
                    .foregroundStyle(Self.qualifierColor(for: component))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(Self.Describe(component: component))
    }

    /// One signal per line once the type is large.
    ///
    /// A quarter of the card is 88 points wide. At the largest accessibility
    /// size "Optimal" wants about 180 and "64 ms" about 140, so four columns
    /// stop being a layout and become four truncations — and the reading is
    /// the whole point of this strip. Full width per signal costs three rows
    /// of height on a screen that is already scrolling.
    private func row(for component: RecoveryScore.Component) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: Self.symbol(for: component.label))
                .font(Theme.text(15, weight: .semibold))
                .foregroundStyle(Self.tint(for: component.label))
                .frame(width: 26, alignment: .leading)

            Text(Self.shortLabel(for: component.label))
                .font(Theme.label(11, weight: .semibold))

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(component.isAvailable ? component.detail : "—")
                    .font(Theme.label(12, weight: .bold))
                    .monospacedDigit()

                Text(Self.qualifier(for: component))
                    .font(Theme.text(11))
                    .foregroundStyle(Self.qualifierColor(for: component))
            }
            .multilineTextAlignment(.trailing)
        }
        .modifier(Self.Describe(component: component))
    }

    /// The same spoken description either way round, so the layout switch
    /// cannot quietly change what VoiceOver reads.
    private struct Describe: ViewModifier {
        let component: RecoveryScore.Component
        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    component.isAvailable
                        ? "\(component.label), \(component.detail), \(ScoreDrivers.qualifier(for: component))"
                        : "\(component.label), not measured"
                )
        }
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
