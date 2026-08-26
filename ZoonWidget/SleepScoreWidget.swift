import WidgetKit
import SwiftUI
import AppIntents

/// Last night's score and headline.
///
/// A second, separate widget rather than another family on the first one:
/// families are chosen by the system based on where you place it, but *which
/// number you care about* is a user preference. Someone tracking recovery wants
/// the score; someone digging out of a bad fortnight wants the debt.
struct SleepScoreWidget: Widget {

    let kind = "ZoonSleepScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepTimelineProvider()) { entry in
            SleepScoreWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last Night")
        .description("Your sleep score and how the night went.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct SleepScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepEntry

    private var snapshot: SleepSnapshot { entry.snapshot }

    /// Mirrors the same "Last Night"/"Last Sleep" switch the app's own
    /// Today/Settings views make on `isShiftWorkModeEnabled` -- carried on
    /// the snapshot itself since the widget process never reads
    /// `UserPreferences` directly (see `SleepSnapshot`'s doc comment).
    private var lastNightLabel: String {
        snapshot.isShiftWorkModeEnabled ? "Last Sleep" : "Last Night"
    }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    /// "Large: Morning Brief" -- the redesign spec's largest widget size,
    /// built entirely from fields `SleepSnapshot` already carries (score,
    /// insight text, sleep intelligence, recovery, energy). The spec also
    /// pairs this with a "Tonight Plan" (caffeine cutoff, wind-down, target
    /// bedtime) -- there's no such data on `SleepSnapshot` yet, and
    /// inventing placeholder values for a widget would be worse than not
    /// having the section, so this is the morning-brief half only.
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(snapshot.score)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.scoreBand)
                        .font(.subheadline.weight(.semibold))
                    Text(lastNightLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(snapshot.insightSummary)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            Divider()

            HStack(spacing: 18) {
                stat("Asleep", SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))
                stat("Debt", snapshot.balanceLabel)
                stat("Recovery", "\(snapshot.recoveryPercent)")
                stat("Energy", "\(snapshot.bodyBattery)")
                if !snapshot.sleepIntelligenceBand.isEmpty {
                    stat("Sleep Intel", "\(snapshot.sleepIntelligencePercent)")
                }
            }

            Spacer(minLength: 0)

            if entry.isPlaceholder {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.tertiary)
            } else {
                Button(intent: OpenJournalIntent()) {
                    Label("Log a habit", systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.Metric.sleep)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(lastNightLabel, systemImage: "bed.double.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Spacer(minLength: 0)

            Text("\(snapshot.score)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(scoreColor)

            Text(snapshot.scoreBand)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("\(snapshot.score)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
                Text(snapshot.scoreBand)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.insightSummary)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    stat("Asleep", SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))
                    stat("Debt", snapshot.balanceLabel)
                    // A snapshot from before this field existed decodes with
                    // an empty band -- omit the stat rather than show a
                    // misleading "0".
                    if !snapshot.sleepIntelligenceBand.isEmpty {
                        stat("Sleep Intel", "\(snapshot.sleepIntelligencePercent)")
                    }
                }

                if entry.isPlaceholder {
                    Text("Sample data")
                        .font(Theme.text(9))
                        .foregroundStyle(.tertiary)
                } else {
                    // The one action worth surfacing here: journaling only
                    // matters if it happens close to when something occurred,
                    // and "open the app, tap Journal, tap the tab" is exactly
                    // the friction that makes people skip it.
                    Button(intent: OpenJournalIntent()) {
                        Label("Log a habit", systemImage: "square.and.pencil")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Metric.sleep)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(lastNightLabel, systemImage: "bed.double.fill")
                .font(.caption2)
                .widgetAccentable()
            // `.privacySensitive()` -- the score and its interpretation are
            // exactly the kind of health signal the redesign audit found
            // showing unconditionally on the Lock Screen, with no way to
            // hide it there independent of the device's own passcode. This
            // opts these two lines into the system's own Lock Screen
            // privacy redaction (Settings > Notifications > Show Previews),
            // the same mechanism first-party widgets use.
            Text("\(snapshot.score) · \(snapshot.scoreBand)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .privacySensitive()
            Text(snapshot.insightSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        // `large`/`medium` pack up to 5 of these into a fixed-width row with
        // no wrapping fallback -- at the larger accessibility text sizes
        // (which .caption/Theme.text both scale with, correctly) that row
        // would otherwise overflow the widget's fixed width and clip off
        // the edge rather than shrink. `minimumScaleFactor` gives it
        // somewhere to go instead.
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.text(9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Reads the same thresholds `SleepScore.Band` uses (`SleepScoreTests`
    /// covers those boundaries) rather than re-deriving them here, so the
    /// widget's color bands can't silently drift out of sync with the
    /// score's own definition of poor/fair/good/excellent.
    private var scoreColor: Color {
        switch SleepScore.Band.forValue(snapshot.score) {
        case .poor: .orange
        case .fair: .yellow
        case .good: .mint
        case .excellent: .green
        }
    }
}

#Preview("Small", as: .systemSmall) {
    SleepScoreWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: false)
    SleepEntry(date: .now, snapshot: MockData.poorSnapshot, isPlaceholder: false)
}

#Preview("Medium", as: .systemMedium) {
    SleepScoreWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: false)
    SleepEntry(date: .now, snapshot: MockData.poorSnapshot, isPlaceholder: true)
}

#Preview("Large", as: .systemLarge) {
    SleepScoreWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: false)
    SleepEntry(date: .now, snapshot: MockData.poorSnapshot, isPlaceholder: true)
}
