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
        // The V9 spec's preferred set, in the order the day asks for them:
        // Sleep Intelligence in the morning, Recovery through the day,
        // Tonight in the evening, Body Signals contextually.
        SleepIntelligenceComplication()
        RecoveryComplication()
        TonightComplication()
        BodySignalsComplication()
        SleepBankComplication()
        // `BadgeComplication` is deliberately absent. The spec: badges "can
        // remain elsewhere but should not consume prime complication
        // space". They are still on the watch's More page and in the phone
        // app; what they no longer do is compete for a watch face slot with
        // the four numbers that describe the body. The type is kept rather
        // than deleted so restoring it is a one-line change if that call
        // turns out to be wrong.
    }
}

// MARK: - Provider

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepSnapshot
    let isPlaceholder: Bool
    /// Which complication this entry is for. Relevance is per-surface, so
    /// the entry has to know which surface it belongs to.
    var kind: WatchRelevance.Kind = .lastNight

    /// What the Smart Stack ranks this by.
    ///
    /// This used to be one score shared by every complication in the
    /// bundle, computed from how recently the phone had synced. That is a
    /// *freshness* signal, not a relevance one -- and with all four scoring
    /// identically the Smart Stack had nothing to order them by, which is
    /// the same as not implementing relevance at all.
    ///
    /// `WatchRelevance` decides the ordering; freshness still gates it,
    /// because a stale number is not worth raising however well its hour
    /// matches. The two are separate judgments and are kept separate.
    var relevance: TimelineEntryRelevance? {
        guard !isPlaceholder else { return TimelineEntryRelevance(score: 10) }
        let hoursSinceGenerated = date.timeIntervalSince(snapshot.generatedAt) / 3600
        let isStale = hoursSinceGenerated < 0 || hoursSinceGenerated >= 24
        // The watch widget extension has no way to observe a running nap --
        // nothing in the snapshot carries one, and a nap surfaces today as
        // a Live Activity on the phone. `WatchRelevance` handles the case
        // and is tested for it; this call site simply has nothing to tell
        // it yet, and says so rather than guessing.
        let score = WatchRelevance.score(for: kind, at: date, isNapRunning: false)
        return TimelineEntryRelevance(
            score: isStale ? min(score, WatchRelevance.outOfWindowScore) : score,
            duration: WatchRelevance.duration
        )
    }
}

struct WatchComplicationProvider: TimelineProvider {

    /// Which complication this provider feeds, so its entries can carry a
    /// relevance that is about this surface rather than about the bundle.
    let kind: WatchRelevance.Kind

    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(
            date: .now, snapshot: MockData.snapshot, isPlaceholder: true, kind: kind
        )
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
            return WatchComplicationEntry(
                date: .now, snapshot: snapshot, isPlaceholder: false, kind: kind
            )
        }
        return WatchComplicationEntry(
            date: .now, snapshot: MockData.snapshot, isPlaceholder: true, kind: kind
        )
    }
}

// MARK: - Sleep Intelligence

/// The morning primary, and the pinnable "Last Night" widget of V9 item 34.
///
/// This is the number the phone's hero, the watch's first page and the
/// widgets all lead with, so a face showing it is showing the same figure as
/// every other surface. The rectangular family carries the spec's full
/// line-up -- score, band, duration, debt -- because that family has the
/// room and it is the one people pin.
struct SleepIntelligenceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "ZoonSleepIntelligence",
            provider: WatchComplicationProvider(kind: .lastNight)
        ) { entry in
            SleepIntelligenceComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last Night")
        .description("Your Sleep Intelligence score for last night.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct SleepIntelligenceComplicationView: View {

    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    /// `flagshipScore`, not `score`: a payload carrying Sleep Intelligence
    /// shows it, and one written before Sleep Intelligence existed falls
    /// back to the older sleep score rather than to a confident-looking 0.
    private var percent: Int { entry.snapshot.flagshipScore }
    private var band: String { entry.snapshot.flagshipBand }

    var body: some View {
        if entry.snapshot.scoreLightMode {
            ScoreLightSnapshotView(snapshot: entry.snapshot)
        } else {
        switch family {
        case .accessoryInline:
            Text("Sleep \(percent)")
                .privacySensitive()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Last Night", systemImage: "moon.stars.fill")
                    .font(Theme.text(13, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(percent)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(entry.isPlaceholder ? "Sample" : band)
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
                .privacySensitive()
                Text("\(SleepNightFeatures.formatMinutes(entry.snapshot.timeAsleepMinutes))  ·  \(entry.snapshot.balanceLabel)")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }

        default:
            Gauge(value: Double(percent), in: 0...100) {
                Image(systemName: "moon.stars.fill")
            } currentValueLabel: {
                Text("\(percent)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .privacySensitive()
        }
        }
    }
}

// MARK: - Body Signals

/// The contextual one: whether anything about the body is drifting from its
/// own baseline.
///
/// Unlike the other three this is usually not news -- most days nothing is
/// moving, and the complication says so plainly rather than manufacturing a
/// number to justify its slot. That is why the spec files it as contextual:
/// its value is that it is quiet until it isn't.
struct BodySignalsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "ZoonBodySignals",
            provider: WatchComplicationProvider(kind: .bodySignals)
        ) { entry in
            BodySignalsComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Body Signals")
        .description("Whether any of your vitals are drifting from baseline.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct BodySignalsComplicationView: View {

    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var isNormal: Bool { entry.snapshot.bodySignalsLabel == "Nothing unusual" }
    private var symbol: String { isNormal ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right" }

    /// "Typical" rather than the stored "Nothing unusual": the complication
    /// has one line, and the spec's own wording for the quiet state is the
    /// shorter one.
    private var summary: String { isNormal ? "Typical" : entry.snapshot.bodySignalsLabel }

    var body: some View {
        if entry.snapshot.scoreLightMode {
            ScoreLightSnapshotView(snapshot: entry.snapshot)
        } else {
        switch family {
        case .accessoryInline:
            Text("Signals \(summary)")
                .privacySensitive()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Body Signals", systemImage: symbol)
                    .font(Theme.text(13, weight: .semibold))
                Text(summary)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .privacySensitive()
                if entry.isPlaceholder {
                    Text("Sample data")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
            }

        default:
            // No gauge: there is no percentage here, and a ring drawn at an
            // arbitrary fill would imply a measurement that does not exist.
            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(isNormal ? "OK" : "Drift")
                    .font(.system(size: 11, weight: .semibold))
            }
            .privacySensitive()
        }
        }
    }
}

// MARK: - Recovery

struct RecoveryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonRecovery", provider: WatchComplicationProvider(kind: .recovery)) { entry in
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

    /// Recovery's own band, derived from Recovery's own percent.
    ///
    /// This used to render `snapshot.scoreBand`, which is the *sleep* score's
    /// band. The two are different measurements of different things, so the
    /// complication could read "Recovery 41%" under the word "Excellent" --
    /// the night having gone well says nothing about how recovered the body
    /// is, which is the entire reason Recovery exists as a separate number.
    ///
    /// Derived here rather than published into the snapshot: the mapping is
    /// `RecoveryScore.Band.forPercent`, it lives in `Shared`, and a second
    /// wire field would be another thing to keep in sync with the decoder.
    private var band: String { RecoveryScore.Band.forPercent(percent).label }

    /// The same refusal the phone and the watch's Today page make. A face
    /// reading "Recovery 66" off four nights asserts exactly as firmly as
    /// one off a month; `canStateRecovery` is how the phone says which it
    /// is, and a complication that ignored it would be the one surface
    /// still overstating the number.
    private var canState: Bool { entry.snapshot.canStateRecovery }

    var body: some View {
        if entry.snapshot.scoreLightMode {
            ScoreLightSnapshotView(snapshot: entry.snapshot)
        } else {
        switch family {
        case .accessoryInline:
            // Inline is a single line of system-styled text; no layout of our
            // own survives here, so it says the least and says it plainly.
            Text(canState ? "Recovery \(percent)%" : "Recovery limited data")
                .privacySensitive()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Recovery", systemImage: "bolt.heart.fill")
                    .font(Theme.text(13, weight: .semibold))
                if canState {
                    Text("\(percent)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .privacySensitive()
                    Text(entry.isPlaceholder ? "Sample data" : band)
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                } else {
                    Text("Limited data")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

        default:
            // Covers both `.accessoryCorner` and `.accessoryCircular` -- the
            // two render identically here (a gauge has no room to say
            // anything else), so there's no reason to case them separately.
            if canState {
                Gauge(value: Double(percent), in: 0...100) {
                    Image(systemName: "bolt.heart.fill")
                } currentValueLabel: {
                    Text("\(percent)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .privacySensitive()
            } else {
                // A ring drawn at 66% is a claim, and an empty one would read
                // as a bad night rather than as an unanswerable question.
                VStack(spacing: 1) {
                    Image(systemName: "bolt.heart")
                        .font(.system(size: 15, weight: .semibold))
                    Text("--")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
        }
        }
    }
}

// MARK: - Sleep bank

struct SleepBankComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonSleepBank", provider: WatchComplicationProvider(kind: .lastNight)) { entry in
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
        if entry.snapshot.scoreLightMode {
            ScoreLightSnapshotView(snapshot: entry.snapshot)
        } else {
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
            Gauge(value: Double(entry.snapshot.flagshipScore), in: 0...100) {
                Image(systemName: "moon.stars.fill")
            } currentValueLabel: {
                Text("\(entry.snapshot.flagshipScore)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .privacySensitive()
        }
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
        StaticConfiguration(kind: "ZoonTonight", provider: WatchComplicationProvider(kind: .tonight)) { entry in
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
        if entry.snapshot.scoreLightMode {
            ScoreLightSnapshotView(snapshot: entry.snapshot)
        } else {
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
}

// MARK: - Badges

struct BadgeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZoonWatchBadges", provider: WatchComplicationProvider(kind: .lastNight)) { entry in
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
        if entry.snapshot.scoreLightMode {
            ScoreLightSnapshotView(snapshot: entry.snapshot)
        } else {
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

// The two complications the V9 spec added to the preferred set.

#Preview("Last Night rectangular", as: .accessoryRectangular) {
    SleepIntelligenceComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: false)
}

#Preview("Last Night circular", as: .accessoryCircular) {
    SleepIntelligenceComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: false)
}

/// Both states, because the quiet one is the one people will actually see
/// most days and is the easier of the two to get wrong.
#Preview("Body Signals rectangular", as: .accessoryRectangular) {
    BodySignalsComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: MockData.snapshotWithBadges, isPlaceholder: false)
    WatchComplicationEntry(date: .now, snapshot: {
        var snapshot = MockData.snapshotWithBadges
        snapshot.bodySignalsLabel = "Several signals moving"
        return snapshot
    }(), isPlaceholder: false)
}

/// The refusal, which is otherwise the state nobody ever looks at.
#Preview("Recovery - limited data", as: .accessoryRectangular) {
    RecoveryComplication()
} timeline: {
    WatchComplicationEntry(date: .now, snapshot: {
        var snapshot = MockData.snapshotWithBadges
        snapshot.recoveryConfidence = MetricConfidence.insufficient.rawValue
        return snapshot
    }(), isPlaceholder: false)
}
