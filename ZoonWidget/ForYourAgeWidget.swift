import WidgetKit
import SwiftUI

/// Last night against the sleep range for your age, and where your heart
/// settled.
///
/// Everything is pre-computed on the phone (`SleepSnapshot.ageRangeLabel`,
/// `heartLowBPM`): the extension has no age, no night history and no
/// heart-rate series of its own.
struct ForYourAgeWidget: Widget {

    let kind = "ZoonForYourAgeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepTimelineProvider(kind: .lastNight)) { entry in
            ForYourAgeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetNightGround() }
        }
        .configurationDisplayName("For Your Age")
        .description("Last night against the sleep range for your age, and your heart's overnight low.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct ForYourAgeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepEntry

    private var snapshot: SleepSnapshot { entry.snapshot }
    private var hasRange: Bool { snapshot.ageRangeHighMinutes > 0 }
    private var hasHeart: Bool { snapshot.heartLowBPM > 0 }

    private var fitText: String {
        guard hasRange else { return "Add your age in Zoon" }
        let asleep = snapshot.timeAsleepMinutes
        if asleep < snapshot.ageRangeLowMinutes { return "Under your range" }
        if asleep > snapshot.ageRangeHighMinutes { return "Over your range" }
        return "In your range"
    }

    var body: some View {
        if !entry.hasSnapshot {
            WidgetNoDataView(
                title: "For Your Age", systemImage: "person.crop.circle",
                message: "Open Zoon to see how last night compares for your age.",
                inlineText: "Open Zoon for your range"
            )
        } else {
        switch family {
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SnapshotFreshness.nightLabel(for: snapshot, now: entry.date).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .privacySensitive()
            if hasRange { rangeBar }
            Text(fitText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            // Placeholder data is marked, as on every other widget: a
            // home screen never shows invented numbers as measured.
            Text(entry.isPlaceholder ? "Sample data" : (hasRange ? snapshot.ageRangeLabel : " "))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            Divider().overlay(.white.opacity(0.15))
            VStack(alignment: .leading, spacing: 6) {
                Text("HEART ASLEEP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                if hasHeart {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(snapshot.heartLowBPM.rounded()))")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
                        Text("bpm low")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .privacySensitive()
                    if let at = snapshot.heartLowAt {
                        Text("at \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text("Average \(Int(snapshot.heartAverageBPM.rounded())) bpm")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .privacySensitive()
                } else {
                    Text("Wear your watch to bed to see your heart at night.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("For your age", systemImage: "person.crop.circle")
                .font(.caption.weight(.semibold))
            Text("\(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes)) · \(fitText.lowercased())")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .privacySensitive()
            Text(hasHeart ? "Heart low \(Int(snapshot.heartLowBPM.rounded())) bpm" : snapshot.ageRangeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .privacySensitive()
        }
    }

    /// 5 to 11 hours, the recommended band shaded, last night as a dot.
    private var rangeBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x: (Double) -> CGFloat = { minutes in
                CGFloat((min(max(minutes, 300), 660) - 300) / 360) * width
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 6)
                Capsule()
                    .fill(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.7))
                    .frame(width: max(6, x(snapshot.ageRangeHighMinutes) - x(snapshot.ageRangeLowMinutes)), height: 6)
                    .offset(x: x(snapshot.ageRangeLowMinutes))
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .offset(x: x(snapshot.timeAsleepMinutes) - 5)
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
