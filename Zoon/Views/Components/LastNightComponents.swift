import SwiftUI

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
                .foregroundStyle(.secondary)

            ZoonHeroMetric(
                value: context.night.formattedTimeAsleep,
                meaning: "\(context.sleepIntelligence.percent) · \(context.sleepIntelligence.band.label)",
                tint: .primary
            )

            HStack(spacing: 10) {
                Text(context.night.bedtime, format: .dateTime.hour().minute())
                    .monospacedDigit()
                Rectangle()
                    .fill(Theme.Family.sleep.opacity(0.5))
                    .frame(height: 1.5)
                    .frame(maxWidth: 120)
                Text(context.night.wakeTime, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }
            .font(Theme.label(14, weight: .medium))
            .foregroundStyle(.secondary)

            Text(context.night.date, format: .dateTime.weekday(.wide).month().day())
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)

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
                        SleepStoryView()
                    } label: {
                        HStack(spacing: 3) {
                            Text("Full story")
                            Image(systemName: "chevron.right").font(Theme.text(10, weight: .semibold))
                        }
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(Theme.Family.sleep)
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
                definition: ("Sleep Efficiency", "gauge.with.dots.needle.67percent", [
                    "The percentage of your time in bed that you actually spent asleep -- total sleep time divided by time in bed.",
                    "Above 85% is generally considered efficient. A lower number usually means either a long time falling asleep or a lot of time awake overnight, both shown here separately."
                ])
            ),
            Cell(
                id: "waso", label: "Awake overnight", value: SleepNightFeatures.formatMinutes(night.awakeMinutes),
                definition: ("WASO", "moon.zzz", [
                    "Wake After Sleep Onset -- the total time spent awake between falling asleep and your final wake-up, added across every awakening rather than just how many there were.",
                    "Under about 20 minutes total is typical for an efficient night."
                ])
            ),
            Cell(
                id: "wakes", label: "Awakenings", value: "\(night.wakeCount)",
                definition: ("Awakenings", "eye", [
                    "Meaningful wake periods after you first fell asleep, not counting brief stirs before sleep onset. Everyone wakes briefly several times a night without remembering it -- this counts the ones long enough to register.",
                    "There's no universal 'normal' count; it's most useful compared against your own recent nights rather than a fixed target."
                ])
            )
        ]
        if let latency = night.sleepLatencyMinutes {
            result.append(Cell(
                id: "latency", label: "Fell asleep in", value: "\(Int(latency))m",
                definition: ("Sleep Latency", "hourglass", [
                    "The time from getting into bed to your first sustained sleep. Only available when your sleep source records in-bed time -- Apple Watch alone doesn't.",
                    "Under 20 minutes is typical for most people. A latency that's crept up over several nights is often more meaningful than one long night."
                ])
            ))
        }
        if night.hasStageBreakdown {
            result.append(Cell(id: "deep", label: "Deep", value: SleepNightFeatures.formatMinutes(night.deepMinutes)))
            result.append(Cell(id: "rem", label: "REM", value: SleepNightFeatures.formatMinutes(night.remMinutes)))
        }
        result.append(Cell(
            id: "inBed", label: night.timeInBedIsEstimated ? "In bed (est.)" : "In bed",
            value: SleepNightFeatures.formatMinutes(night.timeInBedMinutes),
            definition: night.timeInBedIsEstimated ? ("Estimated Time in Bed", "bed.double", [
                "Your sleep source doesn't record when you got into or out of bed, so this is the span from your first sleep reading to your last -- it leaves out time lying awake before falling asleep or after waking, so it tends to run a little short.",
                "An iPhone sleep schedule or a third-party app that logs in-bed time directly would make this exact instead of estimated."
            ]) : nil
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.tertiary)
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
