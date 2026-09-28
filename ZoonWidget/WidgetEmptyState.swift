import SwiftUI
import WidgetKit

/// What a widget draws when there is no snapshot to draw from.
///
/// That is an ordinary state, not an edge case: a new install, Health
/// access denied, a phone with no sleep source, the moment after Delete
/// Everything. Each of those used to be shown the sample night -- "84 ·
/// Good", "7h 32m", "Heart low 51 bpm" -- with nothing to say it was not
/// theirs, and after Delete Everything it read as data that had survived
/// the deletion. This draws no figure of any kind: the widget's name, and
/// the one thing that changes it.
struct WidgetNoDataView: View {
    @Environment(\.widgetFamily) private var family

    /// The widget's own name, as the gallery shows it.
    let title: String
    let systemImage: String
    /// The Home Screen's sentence: "Open Zoon to see last night here."
    let message: String
    /// The Lock Screen's single line: "Open Zoon for last night".
    let inlineText: String

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: systemImage)
        case .accessoryCircular:
            // An empty track under a dash, the same rendering a withheld
            // score gets, so the slot keeps its shape and claims nothing.
            Gauge(value: 0.0, in: 0.0...1.0) {
                Image(systemName: systemImage)
            } currentValueLabel: {
                Text("—")
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("Nothing to show yet. Open Zoon.")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.caption2)
                    .widgetAccentable()
                Text("Nothing to show yet")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Open Zoon")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// "Sample", beside figures that are not the person's own.
///
/// For sample data on the Home Screen: the gallery's preview, and a
/// snapshot the app wrote while itself showing sample data. The Lock Screen
/// families have no room for this beside a figure, so there the figure is
/// replaced instead (`SleepEntry.accessoryShowsFigures`).
struct WidgetSampleMarker: View {
    var body: some View {
        Text("Sample")
            .font(Theme.text(9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Sample data")
    }
}
