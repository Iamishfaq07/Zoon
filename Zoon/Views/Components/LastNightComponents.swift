import SwiftUI

extension SleepNightFeatures {
    /// A wall-clock time in the zone the night was slept in, not the
    /// device's current one -- a night recorded in London and read in New
    /// York should still say 11:05 PM. Same style `NightShareCard` used.
    func clockString(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// The night's calendar day, e.g. "Tuesday, Mar 4", in the same zone --
    /// `date` is a start-of-day there, which can fall on the previous day
    /// when read from a zone far enough west.
    func dayString(month: Date.FormatStyle.Symbol.Month = .abbreviated) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(month).day()
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// The Sleep tab's opening statement: duration as the hero number, the
/// Sleep Intelligence verdict under it, and the bedtime → wake span as a
/// ribbon. Answers "what happened last night?" before any tool or plan.
struct LastNightHero: View {
    let context: DayContext
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        VStack(spacing: 10) {
            Text(preferences.isShiftWorkModeEnabled ? "Last sleep" : "Last night")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSecondary)

            ZoonHeroMetric(
                value: context.night.formattedTimeAsleep,
                meaning: "\(context.sleepIntelligence.percent) · \(context.sleepIntelligence.band.label)",
                tint: .primary
            )

            // Named ends. Unlabelled, "11:02 PM" here sat above a chart
            // starting at "11:14 PM" (the first sleep) with nothing saying
            // one was bed and the other falling asleep.
            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 2) {
                    Text("In bed")
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.inkTertiary)
                    Text(context.night.clockString(context.night.bedtime))
                        .monospacedDigit()
                }
                Rectangle()
                    .fill(Theme.Family.sleep.opacity(0.5))
                    .frame(height: 1.5)
                    .frame(maxWidth: 120)
                    .padding(.bottom, 8)
                VStack(spacing: 2) {
                    Text("Up")
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.inkTertiary)
                    Text(context.night.clockString(context.night.wakeTime))
                        .monospacedDigit()
                }
            }
            .font(Theme.label(14, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)

            Text(context.night.dayString())
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)

            if context.night.isMock {
                StatusPill(text: "Sample data", systemImage: "wand.and.stars", tint: Theme.Family.sleep)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The night's three most telling moments under the hypnogram, joined by a
/// vertical rule -- fell asleep, the longest or first meaningful awakening,
/// and the longest REM run -- with a link to the full story.
///
/// Reads `SleepStory.build`'s events exactly; nothing here re-derives an
/// event. The pick, by the symbols `SleepStory` itself assigns: "Fell
/// asleep" (`moon.zzz`), the longest "Woke briefly" (`eye`, matched to its
/// stage segment for the duration), and "Woke for the day" (`sun.max`).
/// Falls back to the first three events for a night without staging.
struct SleepStoryMoments: View {
    let story: SleepStory
    let night: SleepNightFeatures

    private var moments: [SleepStory.Event] {
        let events = story.events.sorted { $0.time < $1.time }
        var picked: [SleepStory.Event] = []

        if let onset = events.first(where: { $0.symbol == "moon.zzz" }) {
            picked.append(onset)
        }

        let awakenings = events.filter { $0.symbol == "eye" }
        if let longest = awakenings.max(by: { awakeMinutes(at: $0.time) < awakeMinutes(at: $1.time) }) {
            picked.append(longest)
        }

        if let wake = events.last(where: { $0.symbol == "sun.max" }) {
            picked.append(wake)
        }

        if picked.isEmpty {
            picked = Array(events.prefix(3))
        }
        return picked.sorted { $0.time < $1.time }
    }

    /// Duration of the awake segment starting at `time`, from the night's own
    /// stage data rather than by parsing the event's formatted detail string.
    private func awakeMinutes(at time: Date) -> Double {
        night.stageSegments.first { $0.stage == .awake && abs($0.start.timeIntervalSince(time)) < 1 }?.minutes ?? 0
    }

    var body: some View {
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ZoonSectionHeader("What happened") {
                    NavigationLink {
                        NightHub(initial: .story)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Full story")
                            Image(systemName: "chevron.right").font(Theme.text(10, weight: .semibold))
                        }
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(Theme.Family.sleep)
                        // The words are 14 pt tall; the tap target is the
                        // 44 pt minimum around them, which the audit enforces.
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ZoonTimeline(nodes: moments.map { event in
                    .init(
                        id: event.id,
                        time: event.time,
                        title: event.title,
                        detail: event.detail,
                        symbol: event.symbol,
                        tint: Theme.Family.sleep
                    )
                }, now: .distantPast)
            }
        }
    }
}

/// Last night's numbers as a two-column typographic board -- value large,
/// label small, hairline between rows -- instead of eight identical
/// label/value rows in a card. Each cell opens the metric's trend.
///
/// Same numbers `SleepDetailView.timingCard` showed. Each cell keeps that
/// card's definition text behind an info button, and the one metric with a
/// standing trend screen (duration, via `MetricTrendView`) links to it.
struct SleepMetricBoard: View {
    let night: SleepNightFeatures

    private struct Cell: Identifiable {
        let id: String
        let label: String
        let value: String
        var trend: VitalsStatus.Kind?
        var caveat: String?
        var definition: (title: String, symbol: String, text: [String])?
    }

    private var cells: [Cell] {
        var result: [Cell] = [
            Cell(id: "duration", label: "Asleep", value: night.formattedTimeAsleep, trend: .sleepDuration),
            Cell(
                id: "efficiency", label: "Efficiency", value: "\(Int(night.sleepEfficiencyPercent))%",
                caveat: night.timeInBedIsEstimated ? "in-bed estimated" : nil,
                definition: ("Sleep Efficiency", "gauge.with.dots.needle.67percent", NightDefinitions.efficiency)
            ),
            Cell(
                id: "waso", label: "Awake overnight", value: SleepNightFeatures.formatMinutes(night.awakeMinutes),
                definition: ("WASO", "moon.zzz", NightDefinitions.waso)
            ),
            Cell(
                id: "wakes", label: "Awakenings", value: "\(night.wakeCount)",
                definition: ("Awakenings", "eye", NightDefinitions.awakenings)
            )
        ]
        if let latency = night.sleepLatencyMinutes {
            result.append(Cell(
                id: "latency", label: "Fell asleep in", value: "\(Int(latency))m",
                definition: ("Sleep Latency", "hourglass", NightDefinitions.latency)
            ))
        }
        if night.hasStageBreakdown {
            result.append(Cell(id: "deep", label: "Deep", value: SleepNightFeatures.formatMinutes(night.deepMinutes)))
            result.append(Cell(id: "rem", label: "REM", value: SleepNightFeatures.formatMinutes(night.remMinutes)))
        }
        result.append(Cell(
            id: "inBed", label: night.timeInBedIsEstimated ? "In bed (est.)" : "In bed",
            value: SleepNightFeatures.formatMinutes(night.timeInBedMinutes),
            definition: night.timeInBedIsEstimated ? ("Estimated Time in Bed", "bed.double", NightDefinitions.inBedEstimated) : nil
        ))
        return result
    }

    var body: some View {
        let rows = stride(from: 0, to: cells.count, by: 2).map { Array(cells[$0..<min($0 + 2, cells.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(Theme.cardStroke).frame(height: 1)
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(row) { cell in
                        cellView(cell)
                    }
                    if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                }
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(cell.value)
                .font(Theme.supportingValue)
                .monospacedDigit()
            HStack(spacing: 4) {
                Text(cell.label)
                    .font(Theme.supportingLabel)
                    .foregroundStyle(Theme.inkSecondary)
                if let definition = cell.definition {
                    MetricInfoButton(
                        title: definition.title, symbol: definition.symbol,
                        tint: Theme.Family.sleep, explanation: definition.text
                    )
                }
            }
            if let caveat = cell.caveat {
                Text(caveat)
                    .font(Theme.text(10))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)

        if let trend = cell.trend {
            NavigationLink { MetricTrendView(kind: trend) } label: { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint("Show trend")
        } else {
            content
        }
    }
}

#Preview("Last night components") {
    var night = MockData.poorNight
    night.stageSegments = AppMockData.stageSegments(for: night)
    let story = SleepStory.build(night: night)
    return NavigationStack {
        ScrollView {
            VStack(spacing: 28) {
                LastNightHero(context: AppMockData.dayContext())
                SleepStoryMoments(story: story, night: night)
                SleepMetricBoard(night: night)
            }
            .padding()
        }
        .nightBackground()
    }
    .zoonPreviewEnvironment()
}

/// What the night's timing figures mean, shared by Sleep Detail and the Last
/// Night grid. Each was two long paragraphs, written twice and drifting
/// apart; now it is two short lines in one place.
enum NightDefinitions {
    static let efficiency = [
        "Time asleep divided by time in bed.",
        "Above 85% is efficient. Lower usually means a slow start or time awake."
    ]
    static let efficiencyEstimated = "In-bed time is estimated tonight, so this reads a little high."
    static let waso = [
        "All the time awake between falling asleep and your final wake.",
        "Under about 20 minutes is typical."
    ]
    static let awakenings = [
        "Wake-ups long enough to register. Everyone has a few they don't remember.",
        "Best compared with your own nights, not a fixed number."
    ]
    static let latency = [
        "Bed to first sustained sleep. Needs in-bed time, which a Watch alone doesn't record.",
        "Under 20 minutes is typical. A slow creep over nights matters more than one."
    ]
    static let inBedEstimated = [
        "Your source doesn't log getting into bed, so this runs from first to last sleep reading. It reads a little short.",
        "An iPhone sleep schedule makes it exact."
    ]
}
