import SwiftUI
import WidgetKit

/// Watch face complications.
///
/// On watchOS 9 and later a complication is a WidgetKit widget in an extension
/// embedded in the watch app — the same shape as an iOS widget, with the
/// accessory families only. That is why this extension exists at all: the
/// rendering code is nearly identical to the phone's, but a widget can only be
/// offered by a bundle that lives on the device showing it.
///
/// ## Where the data comes from
///
/// Not HealthKit, and not a shared container. The watch app receives a snapshot
/// over WatchConnectivity and writes it to its own `UserDefaults`; this
/// extension reads that. It is the only channel available: an extension cannot
/// hold a `WCSession`, and the watch app is not running when the face is drawn.
///
/// The consequence is worth being honest about — **a complication shows what
/// the watch last heard from the phone.** If you have not opened Zoon on your
/// phone since last night, the face shows the night before. There is no way
/// around that without a server, and there is not going to be a server.
@main
struct ZoonWatchComplications: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
        SleepBankComplication()
        TonightComplication()
        BadgeComplication()
    }
}

// MARK: - Provider

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepSnapshot
    let isPlaceholder: Bool

    /// Same reasoning as `SleepEntry.relevance` on the phone side: high for
    /// a few hours after the snapshot was generated (closest available
    /// proxy for "just after waking up"), low otherwise, so watchOS's own
    /// Smart Stack has a signal for *when* this complication matters
    /// instead of a flat score.
    var relevance: TimelineEntryRelevance? {
        guard !isPlaceholder else { return TimelineEntryRelevance(score: 10) }
        let hoursSinceGenerated = date.timeIntervalSince(snapshot.generatedAt) / 3600
        let recentlyRefreshed = hoursSinceGenerated >= 0 && hoursSinceGenerated < 4
        return TimelineEntryRelevance(score: recentlyRefreshed ? 80 : 20, duration: 4 * 3600)
    }
}

struct WatchComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WatchComplicationEntry) -> Void
    ) {
        completion(currentEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WatchComplicationEntry>) -> Void
    ) {
        // One entry, refreshed after the small hours. Sleep data changes once a
        // day and the watch app reloads timelines the moment a new snapshot
        // arrives, so a dense timeline would only burn the complication's
        // refresh budget and get the extension throttled — making it less
        // current rather than more.
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> WatchComplicationEntry {
        if let snapshot = WatchSnapshotStore.load() {
            return WatchComplicationEntry(date: .now, snapshot: snapshot, isPlaceholder: false)
        }
        return WatchComplicationEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true)
    }
}

// MARK: - Recovery

struct RecoveryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonRecovery", provider: WatchComplicationProvider()) { entry in
            RecoveryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recovery")
        .description("How recovered you are today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct RecoveryComplicationView: View {

    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var percent: Int { entry.snapshot.recoveryPercent }

    var body: some View {
        switch family {
        case .accessoryInline:
            // Inline is a single line of system-styled text; no layout of our
            // own survives here, so it says the least and says it plainly.
            Text("Recovery \(percent)%")
                .privacySensitive()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Recovery", systemImage: "bolt.heart.fill")
                    .font(Theme.text(13, weight: .semibold))
                Text("\(percent)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .privacySensitive()
                Text(entry.isPlaceholder ? "Sample data" : entry.snapshot.scoreBand)
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }

        default:
            // Covers both `.accessoryCorner` and `.accessoryCircular` -- the
            // two render identically here (a gauge has no room to say
            // anything else), so there's no reason to case them separately.
            Gauge(value: Double(percent), in: 0...100) {
                Image(systemName: "bolt.heart.fill")
            } currentValueLabel: {
                Text("\(percent)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .privacySensitive()
        }
    }
}

// MARK: - Sleep bank

struct SleepBankComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonSleepBank", provider: WatchComplicationProvider()) { entry in
            SleepBankComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sleep Bank")
        .description("Last night, and what you owe yourself.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct SleepBankComplicationView: View {

    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Slept \(SleepNightFeatures.formatMinutes(entry.snapshot.timeAsleepMinutes))")
                .privacySensitive()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                // Mirrors the same "Last Night"/"Last Sleep" switch
                // SleepScoreWidget makes on isShiftWorkModeEnabled.
                Label(
                    entry.snapshot.isShiftWorkModeEnabled ? "Last sleep" : "Last night",
                    systemImage: "moon.stars.fill"
                )
                    .font(Theme.text(13, weight: .semibold))
                Text(SleepNightFeatures.formatMinutes(entry.snapshot.timeAsleepMinutes))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .privacySensitive()
                Text(entry.isPlaceholder ? "Sample data" : "Bank \(entry.snapshot.balanceLabel)")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }

        default:
            // Score rather than duration in the circular slot: a percentage
            // fills a gauge honestly, where "7h 32m" has no natural maximum to
            // draw an arc against.
            Gauge(value: Double(entry.snapshot.score), in: 0...100) {
                Image(systemName: "moon.stars.fill")
            } currentValueLabel: {
                Text("\(entry.snapshot.score)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .privacySensitive()
        }
    }
}

// MARK: - Tonight

/// Tonight's bed and wake target.
///
/// The only complication here about a night that has not happened. The other
/// three all grade the one that has, which makes them a morning glance; this
/// is the evening one, and a watch face is where "when should I be getting
/// into bed" is actually asked.
///
/// No circular family. A gauge needs a value with a natural maximum to draw
/// an arc against -- the same reason `SleepBankComplication` puts the score
/// in its circular slot rather than a duration -- and a bedtime has neither
/// a maximum nor a meaningful fraction. Offering a circular slot that could
/// only show a clipped "23:4" would be worse than not offering one.
struct TonightComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonTonight", provider: WatchComplicationProvider()) { entry in
            TonightComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's bed and wake target.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}

struct TonightComplicationView: View {

    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    /// Empty covers both "no plan yet" and a snapshot written before these
    /// fields existed. The complication cannot tell them apart and does not
    /// need to -- both mean there is no target to show.
    private var hasPlan: Bool { !entry.snapshot.tonightTargetLabel.isEmpty }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(hasPlan ? "Bed \(entry.snapshot.tonightTargetLabel)" : "No target yet")
                .privacySensitive()

        default:
            VStack(alignment: .leading, spacing: 1) {
                Label("Tonight", systemImage: entry.snapshot.isTonightTargetHolding
                      ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle.fill")
                    .font(Theme.text(13, weight: .semibold))
                if hasPlan {
                    Text(entry.snapshot.tonightTargetLabel)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .privacySensitive()
                    // Two words rather than the engine's full sentence: a
                    // rectangular complication has one line left, and the
                    // sentence explains a shift the person can read on the
                    // phone. Whether tonight is a change at all is the part
                    // that fits.
                    Text(entry.isPlaceholder
                         ? "Sample data"
                         : (entry.snapshot.isTonightTargetHolding ? "Your usual night" : "A small shift"))
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                } else {
                    Text("Not enough nights yet")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Badges

struct BadgeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonWatchBadges", provider: WatchComplicationProvider()) { entry in
            BadgeComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Badges")
        .description("How many badges you've earned.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct BadgeComplicationView: View {

    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var hasBadge: Bool { !entry.snapshot.badgeTitle.isEmpty }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.snapshot.badgesUnlocked) badges")
                .privacySensitive()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(hasBadge ? entry.snapshot.badgeTitle : "Badges", systemImage: "hexagon.fill")
                    .font(Theme.text(13, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()
                Text("\(entry.snapshot.badgesUnlocked) of \(entry.snapshot.badgesTotal)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .privacySensitive()
                if entry.isPlaceholder {
                    Text("Sample data")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
            }

        default:
            Gauge(value: Double(entry.snapshot.badgesUnlocked),
                  in: 0...Double(max(1, entry.snapshot.badgesTotal))) {
                Image(systemName: "hexagon.fill")
            } currentValueLabel: {
                Text("\(entry.snapshot.badgesUnlocked)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .privacySensitive()
        }
    }
}

#Preview("Recovery circular", as: .accessoryCircular) {
    RecoveryComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: false)
}

#Preview("Sleep rectangular", as: .accessoryRectangular) {
    SleepBankComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: false)
}

#Preview("Badges rectangular", as: .accessoryRectangular) {
    BadgeComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: false)
}

// Both of Tonight's families, where the three siblings above preview one
// each. It is the only complication here with a state that renders
// perfectly well while saying nothing -- the waiting copy someone sees for
// their first week -- so that state is worth a timeline entry of its own
// rather than being the state nobody ever looks at.

#Preview("Tonight rectangular", as: .accessoryRectangular) {
    TonightComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.tonightSnapshot, isPlaceholder: false)
    WatchComplicationEntry(date: .now, snapshot: MockData.holdingTonightSnapshot, isPlaceholder: false)
    // The three-line rectangular layout with no plan yet.
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: false)
}

#Preview("Tonight inline", as: .accessoryInline) {
    TonightComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.tonightSnapshot, isPlaceholder: false)
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: false)
}
