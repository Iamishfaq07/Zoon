import WidgetKit
import SwiftUI

/// Sleep debt as a "bank balance".
///
/// The framing is the point: hours owed is a number people already know how to
/// read, and it makes an abstract cumulative deficit feel like something you can
/// pay down. Note that it never shows a *positive* balance — you cannot bank
/// surplus sleep, and a widget implying you can would be teaching the wrong
/// lesson. Best case is "Even".
struct SleepDebtWidget: Widget {

    let kind = "ZoonSleepDebtWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepTimelineProvider()) { entry in
            SleepDebtWidgetView(entry: entry)
                // Required from iOS 17: widgets no longer draw their own
                // background, the system does, and omitting this makes the
                // widget render with a broken-looking transparent panel.
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sleep Debt")
        .description("How much sleep you owe yourself over the last two weeks.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

struct SleepDebtWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var snapshot: SleepSnapshot { entry.snapshot }

    /// Mirrors the same "Last Night"/"Last Sleep" switch `SleepScoreWidget`
    /// makes on `snapshot.isShiftWorkModeEnabled`.
    private var lastNightLabel: String {
        snapshot.isShiftWorkModeEnabled ? "Last sleep" : "Last night"
    }

    // MARK: - Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sleep Debt", systemImage: "moon.zzz.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(snapshot.balanceLabel)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(debtColor)

            Text(debtCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(lastNightLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }

            if entry.isPlaceholder { placeholderBadge }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Sleep Debt", systemImage: "moon.zzz.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(snapshot.balanceLabel)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(debtColor)

                Text(debtCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if entry.isPlaceholder { placeholderBadge }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ScoreBadge(score: snapshot.score, band: snapshot.scoreBand)

                Text(snapshot.insightSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Lock screen
    //
    // Accessory families render monochrome — the system applies a vibrancy
    // treatment and discards colour, so these rely on layout and symbols to
    // carry meaning rather than on the red/green the home-screen views use.

    // `.privacySensitive()` throughout below -- the score and debt figures
    // are exactly the kind of health signal the redesign audit found
    // showing unconditionally on the Lock Screen with no way to hide them
    // there independent of the device's own passcode. This opts each
    // data-bearing line into the system's own Lock Screen privacy
    // redaction (Settings > Notifications > Show Previews), the same
    // mechanism first-party widgets use -- labels/icons stay visible so the
    // widget is still identifiable at a glance.

    private var circular: some View {
        Gauge(value: min(Double(snapshot.score), 100), in: 0...100) {
            Image(systemName: "moon.zzz.fill")
        } currentValueLabel: {
            Text("\(snapshot.score)")
                .font(.system(.body, design: .rounded).weight(.semibold))
        }
        .gaugeStyle(.accessoryCircular)
        .privacySensitive()
    }

    private var inline: some View {
        Label(
            "\(snapshot.balanceLabel) sleep · \(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))",
            systemImage: "moon.zzz.fill"
        )
        .privacySensitive()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Sleep Debt", systemImage: "moon.zzz.fill")
                .font(.caption2)
                .widgetAccentable()
            Text(snapshot.balanceLabel)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .privacySensitive()
            Text("\(lastNightLabel) \(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes)) · \(snapshot.score)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bits

    private var debtColor: Color {
        switch snapshot.sleepDebtHours {
        case ..<0.25: .green
        case 0.25..<3: .yellow
        case 3..<8: .orange
        default: .red
        }
    }

    private var debtCaption: String {
        if snapshot.sleepDebtMinutes < 15 {
            return "Square with your goal"
        }
        return "vs \(SleepNightFeatures.formatMinutes(snapshot.goalMinutes))/night, 14 days"
    }

    private var placeholderBadge: some View {
        Text("Sample")
            .font(Theme.text(9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// Small score pill reused across widget families.
struct ScoreBadge: View {
    let score: Int
    let band: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(score)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: -1) {
                Text(band)
                    .font(.caption2.weight(.semibold))
                Text("score")
                    .font(Theme.text(9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    SleepDebtWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: false)
    SleepEntry(date: .now, snapshot: MockData.poorSnapshot, isPlaceholder: false)
}

#Preview("Medium", as: .systemMedium) {
    SleepDebtWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.poorSnapshot, isPlaceholder: false)
    SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    SleepDebtWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.poorSnapshot, isPlaceholder: false)
}

#Preview("Circular", as: .accessoryCircular) {
    SleepDebtWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: false)
}
