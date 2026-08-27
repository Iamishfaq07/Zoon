import WidgetKit
import SwiftUI

/// Tonight's target and tomorrow's likely range.
///
/// The other three widgets all grade a night that has already happened.
/// This is the only one about a night that has not, which is what earns it
/// a place rather than making it a fourth way to look at the same numbers.
/// It is also the one worth glancing at in the evening, when the others
/// have nothing new to say.
///
/// Everything it shows is pre-formatted on the phone. The extension is a
/// separate process with no HealthKit pipeline and no night history, so it
/// could not run `SleepAutopilot` or `UncertaintyForecast` even if they
/// were linked in -- the same reason badges are evaluated phone-side. See
/// `SleepSnapshot.tonightTargetLabel`.
struct TonightWidget: Widget {

    let kind = "ZoonTonightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepTimelineProvider()) { entry in
            TonightWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's bed and wake target, and where tomorrow is likely to land.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct TonightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var snapshot: SleepSnapshot { entry.snapshot }

    /// A snapshot written before these fields existed decodes with empty
    /// strings, and so does one from someone without enough history for a
    /// plan. Both render the same waiting copy rather than an empty box:
    /// the widget cannot tell the two apart, and does not need to.
    private var hasPlan: Bool { !snapshot.tonightTargetLabel.isEmpty }

    private var tint: Color {
        snapshot.isTonightTargetHolding ? Theme.Metric.recoveryHigh : Theme.Metric.sleep
    }

    private var waitingCopy: String {
        "A week or so of nights and Zoon can suggest a target."
    }

    // MARK: - Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tonight", systemImage: "bed.double.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if hasPlan {
                Text(snapshot.tonightTargetLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(tint)

                Text(snapshot.tonightTargetNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text(waitingCopy)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Spacer(minLength: 0)

            if entry.isPlaceholder { placeholderBadge }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Tonight", systemImage: "bed.double.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if hasPlan {
                    Text(snapshot.tonightTargetLabel)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(tint)
                    Text(snapshot.tonightTargetNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text(waitingCopy)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                if entry.isPlaceholder { placeholderBadge }
            }

            if !snapshot.tomorrowRangeLabel.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tomorrow")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.tomorrowRangeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    // Only on medium: the small family has no room for a
                    // button under a three-line note, and a control that
                    // squeezes the content it sits under is worse than no
                    // control. Placeholder entries get no button because
                    // there is nothing real behind it to open.
                    if !entry.isPlaceholder {
                        Button(intent: OpenPatternsIntent()) {
                            Label("See the range", systemImage: "chart.dots.scatter")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.Metric.strain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Lock screen

    /// One line, so it carries the target rather than the reason -- the
    /// reason is the part that does not fit, not the part that matters at a
    /// glance.
    private var inline: some View {
        Text(hasPlan ? "Tonight \(snapshot.tonightTargetLabel)" : "Tonight: no target yet")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tonight")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if hasPlan {
                Text(snapshot.tonightTargetLabel)
                    .font(.headline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(snapshot.isTonightTargetHolding ? "Your usual night" : "A small shift")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No target yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholderBadge: some View {
        Text("Sample")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}
