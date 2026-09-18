import SwiftUI

/// The four recovery signals as readings, not just as colours.
///
/// The ring's legend named the signals; it never said what any of them
/// actually measured. "HRV" tells you nothing you did not already know —
/// "HRV 81 ms, optimal" is the sentence people want, and every part of it was
/// already computed and thrown away.
///
/// The line under each reading states that signal in its own terms — HRV
/// and resting heart rate against this person's own baseline, respiration
/// against its usual range, sleep against the target it was measured on.
/// `RecoveryDriverSemantics` owns that wording and documents why one shared
/// scale across all four was wrong. An unmeasured signal says so rather than
/// scoring.
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

                reading(for: component)

                Text(Self.qualifier(for: component))
                    .font(Theme.text(11))
                    .foregroundStyle(Self.qualifierColor(for: component))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(Self.Describe(component: component))
    }

    @ViewBuilder
    private func reading(for component: RecoveryScore.Component) -> some View {
        let parts = MetricReading.split(component.isAvailable ? component.detail : "—")
        Text(parts.value)
            .font(Theme.label(12, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        if let unit = parts.unit {
            Text(unit)
                .font(Theme.text(10))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// One signal per line once the type is large.
    ///
    /// A quarter of the card is 88 points wide. At the largest accessibility
    /// size "Optimal" wants about 180 and "64 ms" about 140, so four columns
    /// stop being a layout and become four truncations — and the reading is
    /// the whole point of this strip. Full width per signal costs three rows
    /// of height on a screen that is already scrolling.
    ///
    /// One size further on, the same squeeze returns in miniature. The AX5
    /// capture shows the label and the value sharing a line while the
    /// qualifier, pinned to the right column beneath the value, wraps --
    /// "Near / baseline" over two lines. Three lines per signal, one of them
    /// a broken phrase.
    ///
    /// So at the top two sizes the qualifier stops being a right column and
    /// takes the full width under the pair. The label and the value keep
    /// their line, because that pairing is what somebody scans; the reading
    /// gets the room it needs to stay one phrase. Three lines become two,
    /// and nothing wraps.
    private func row(for component: RecoveryScore.Component) -> some View {
        Group {
            if dynamicTypeSize >= .accessibility4 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        driverIcon(for: component)
                        driverLabel(for: component)
                        Spacer(minLength: 8)
                        driverValue(for: component)
                    }
                    driverQualifier(for: component)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    driverIcon(for: component)
                    driverLabel(for: component)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        driverValue(for: component)
                        driverQualifier(for: component)
                    }
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .modifier(Self.Describe(component: component))
    }

    private func driverIcon(for component: RecoveryScore.Component) -> some View {
        Image(systemName: Self.symbol(for: component.label))
            .font(Theme.text(15, weight: .semibold))
            .foregroundStyle(Self.tint(for: component.label))
            .frame(width: 26, alignment: .leading)
    }

    private func driverLabel(for component: RecoveryScore.Component) -> some View {
        Text(Self.shortLabel(for: component.label))
            .font(Theme.label(11, weight: .semibold))
    }

    private func driverValue(for component: RecoveryScore.Component) -> some View {
        Text(component.isAvailable ? component.detail : "—")
            .font(Theme.label(12, weight: .bold))
            .monospacedDigit()
    }

    private func driverQualifier(for component: RecoveryScore.Component) -> some View {
        Text(Self.qualifier(for: component))
            .font(Theme.text(11))
            .foregroundStyle(Self.qualifierColor(for: component))
    }

    /// The same spoken description either way round, so the layout switch
    /// cannot quietly change what VoiceOver reads.
    private struct Describe: ViewModifier {
        let component: RecoveryScore.Component
        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .combine)
                // Units spelled out and the relationship stated: "HRV, 50
                // milliseconds, below your baseline" rather than "HRV, 50 em
                // ess, low". For HRV especially there is no population answer
                // to what "low" means.
                .accessibilityLabel(RecoveryDriverSemantics.accessibilityLabel(for: component))
        }
    }

    /// Each signal in its own terms — see `RecoveryDriverSemantics` for why
    /// one scale across all four was wrong.
    ///
    /// Briefly: the four `normalized` values answer different questions, so a
    /// person whose HRV and resting heart rate were exactly normal for them
    /// read "Fair" on both while their equally normal respiration read
    /// "Optimal". The words were describing arithmetic conventions rather
    /// than the body.
    private static func qualifier(for component: RecoveryScore.Component) -> String {
        RecoveryDriverSemantics.reading(for: component).phrase
    }

    /// Colour only where a reader might act on it.
    ///
    /// Previously every signal got a verdict hue — four rows of red, amber or
    /// green under a hero ring that is itself a three-stop gradient, so the
    /// screen ran five colour languages at once and none of them led.
    /// "Near baseline" and "above your baseline" are ordinary ink now; only a
    /// reading that sits away from baseline in the direction that matters
    /// takes a colour, and it takes one colour rather than a green/red pair.
    private static func qualifierColor(for component: RecoveryScore.Component) -> Color {
        let reading = RecoveryDriverSemantics.reading(for: component)
        return switch reading.standing {
        case .unmeasured: Theme.inkTertiary
        case .notable: Theme.Family.attention
        case .typical, .favourable: Theme.inkSecondary
        }
    }

    /// Deliberately neutral.
    ///
    /// This strip was running two colour languages at once: a family hue per
    /// signal on the icon, and a verdict hue on the qualifier beneath it.
    /// Four rows, eight colour decisions, under a hero ring that is itself a
    /// three-stop gradient -- so the screen showed five or more strong hues
    /// competing, and none of them dominated.
    ///
    /// The verdict colour is the one carrying something a reader acts on.
    /// The family hue was identity, and the symbol beside it already says
    /// which signal this is. So the icon steps back and the verdict keeps its
    /// colour, which leaves the ring as the screen's one accent.
    ///
    /// The family hues are not gone -- they are what the ring's own signal
    /// markers use, and what each metric's detail screen opens in. Colour
    /// arrives on selection rather than all at once.
    private static func tint(for label: String) -> Color {
        _ = label
        return Theme.inkSecondary
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
