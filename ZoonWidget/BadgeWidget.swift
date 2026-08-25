import SwiftUI
import WidgetKit

/// Badge progress, on the home screen and the lock screen.
///
/// The accessory families here are the same ones watchOS uses for
/// complications, so this view is already the watch face rendering — the watch
/// app just has to exist for the system to offer it.
struct BadgeWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonBadges", provider: SleepTimelineProvider()) { entry in
            BadgeWidgetView(snapshot: entry.snapshot, isPlaceholder: entry.isPlaceholder)
                // Matches the other widgets: the system material, not the
                // app's gradient. A widget that paints its own dark background
                // fights the home screen's tinting rather than sitting in it.
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Badges")
        .description("Your latest badge and the one you're closest to.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular
        ])
    }
}

struct BadgeWidgetView: View {

    let snapshot: SleepSnapshot
    /// True when this is sample data because no real snapshot was readable.
    ///
    /// Flagged on screen, like the other widgets do. A home screen must never
    /// present an invented health number as a measured one, and the badge count
    /// is exactly the kind of number someone would otherwise believe.
    var isPlaceholder = false

    @Environment(\.widgetFamily) private var family

    private var tint: Color {
        switch snapshot.badgeTier {
        case 2: Color(red: 1.00, green: 0.78, blue: 0.31)
        case 1: Color(red: 0.76, green: 0.80, blue: 0.87)
        default: Color(red: 0.80, green: 0.53, blue: 0.32)
        }
    }

    private var hasBadge: Bool { !snapshot.badgeTitle.isEmpty }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: - Home screen

    private var small: some View {
        VStack(spacing: 8) {
            badgeMark(size: 46)

            Text(hasBadge ? snapshot.badgeTitle : "No badges yet")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)

            Text(isPlaceholder ? "Sample" : "\(snapshot.badgesUnlocked) of \(snapshot.badgesTotal)")
                .font(.system(size: 10, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            badgeMark(size: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(hasBadge ? snapshot.badgeTitle : "No badges yet")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(isPlaceholder
                     ? "Sample data — open Zoon to see yours"
                     : "\(snapshot.badgesUnlocked) of \(snapshot.badgesTotal) earned")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if !snapshot.nextBadgeTitle.isEmpty {
                    Divider().overlay(Color.white.opacity(0.12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next: \(snapshot.nextBadgeTitle)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        ProgressView(value: snapshot.nextBadgeProgress)
                            .tint(tint)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func badgeMark(size: CGFloat) -> some View {
        ZStack {
            WidgetHexagon()
                .fill(
                    LinearGradient(
                        colors: hasBadge
                        ? [tint.opacity(0.9), tint.opacity(0.4)]
                        : [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size * 1.1)

            Image(systemName: hasBadge ? snapshot.badgeSymbol : "hexagon")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(hasBadge ? .black : .secondary)
        }
    }

    // MARK: - Lock screen and watch face
    //
    // Accessory families are rendered by the system in a single tint — colour
    // is unavailable by design. Everything here has to read as shape and
    // number alone, which is why the circular variant is a gauge rather than
    // a scaled-down badge.

    private var circular: some View {
        Gauge(value: Double(snapshot.badgesUnlocked),
              in: 0...Double(max(1, snapshot.badgesTotal))) {
            Image(systemName: "hexagon.fill")
        } currentValueLabel: {
            Text("\(snapshot.badgesUnlocked)")
                .monospacedDigit()
                .privacySensitive()
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(hasBadge ? snapshot.badgeTitle : "No badges yet", systemImage: "hexagon.fill")
                .font(Theme.text(13, weight: .semibold))
                .lineLimit(1)
                .privacySensitive()

            Text(isPlaceholder
                 ? "Sample data"
                 : "\(snapshot.badgesUnlocked) of \(snapshot.badgesTotal) earned")
                .font(Theme.text(12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .privacySensitive()

            if !snapshot.nextBadgeTitle.isEmpty {
                Text("Next: \(snapshot.nextBadgeTitle)")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
    }
}

/// Same shape as the app's `Hexagon`, duplicated rather than shared.
///
/// `Hexagon` lives in `Zoon/Views/`, which is app-only. Moving it to `Shared/`
/// to save fifteen lines would put a view type in the module boundary that
/// exists to carry *data* between the two targets, and that boundary staying
/// narrow is what keeps the widget unable to reach HealthKit.
struct WidgetHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.25))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.75))
        path.addLine(to: CGPoint(x: rect.minX + w / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.75))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.25))
        path.closeSubpath()
        return path
    }
}

#Preview("Badges small", as: .systemSmall) {
    BadgeWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: true)
}

#Preview("Badges medium", as: .systemMedium) {
    BadgeWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: true)
}

#Preview("Badges rectangular", as: .accessoryRectangular) {
    BadgeWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: true)
}
