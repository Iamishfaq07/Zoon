import SwiftUI
import Charts

/// Trends over 7 or 30 days.
///
/// Charts read from `coordinator.recentNights`, which is stored history — so
/// this screen works offline, instantly, with no HealthKit round trip.
struct TrendsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    @State private var window: Window = .week

    enum Window: String, CaseIterable, Identifiable {
        case week = "7 Days"
        case month = "30 Days"

        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    private var nights: [SleepNightFeatures] {
        Array(coordinator.recentNights.suffix(window.days))
    }

    /// Debt-in-minutes for each night in `nights`, aligned by index.
    ///
    /// Computed over `coordinator.recentNights` in full, not the already-
    /// sliced `nights` -- see `SleepDebtChartCard`'s doc comment for why a
    /// night's debt needs decayed context from before the display window.
    private var debtMinutesForDisplayedNights: [Double] {
        // total24hAsleepMinutes, not timeAsleepMinutes alone, and each
        // night's own frozen sleepNeedBaselineMinutes, not the current
        // Settings goal uniformly -- both so this matches the exact
        // accounting SleepHistoryStore uses to compute the live
        // sleepDebtMinutes shown elsewhere. See that property's doc comment.
        let fullSeries = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: coordinator.recentNights.map(\.total24hAsleepMinutes),
            goalMinutesOldestFirst: coordinator.recentNights.map { $0.sleepNeedBaselineMinutes ?? preferences.sleepGoalMinutes }
        )
        return Array(fullSeries.suffix(window.days))
    }

    /// Journal tags per night, so the duration chart's tap-to-inspect badge
    /// can show what was logged alongside the sleep number -- "annotations"
    /// per the spec, kept lightweight: no icons crowding the chart itself,
    /// just context on the selection that's already there.
    private var tagsByDate: [Date: Set<BehaviorTag>] {
        Dictionary(uniqueKeysWithValues: coordinator.journal.allEntries().map { ($0.date, Set($0.tags)) })
    }

    /// `nil` unless cycle tracking is on and there's at least one logged
    /// period start — both a privacy gate and a "don't show an empty card"
    /// gate, in one property.
    private var cycleCorrelations: [CyclePhaseCorrelation]? {
        guard preferences.cycleTrackingEnabled, !coordinator.cyclePeriodStarts.isEmpty else { return nil }
        let inputs = coordinator.recentNights.map { night in
            (
                date: night.date,
                recoveryPercent: coordinator.recoveryHistory[night.date] ?? 50,
                // Duration against goal, as a lightweight stand-in for the full
                // debt-and-strain-adjusted sleep-need calculation — good enough
                // for a phase-to-phase comparison, not a claim of precision.
                sleepPerformance: min(150, night.timeAsleepMinutes / preferences.sleepGoalMinutes * 100)
            )
        }
        let result = CyclePhaseCorrelation.compute(nights: inputs, periodStarts: coordinator.cyclePeriodStarts)
        return result.isEmpty ? nil : result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stackSpacing) {
                    InsightsHero(goalMinutes: preferences.sleepGoalMinutes)
                    WhatChangedCard(nights: coordinator.recentNights, goalMinutes: preferences.sleepGoalMinutes)
                    DiscoveriesCard(
                        findings: JournalCorrelator().findings(from: coordinator.journalObservations()),
                        activeExperiment: preferences.activeExperimentTag.map { tag in
                            (tag, GuidedExperiment.status(
                                for: tag,
                                observations: coordinator.journalObservations(),
                                since: preferences.experimentStartDate
                            ))
                        }
                    )
                    if let context = coordinator.state.context {
                        CoreIntelligenceGrid(context: context)
                    }
                    insightsHub

                    if nights.count < 2 {
                        notEnoughData
                    } else {
                        windowPicker
                        DurationChartCard(nights: nights, goalMinutes: preferences.sleepGoalMinutes, tagsByDate: tagsByDate)
                        HRVChartCard(nights: nights)
                        SleepDebtChartCard(nights: nights, debtMinutes: debtMinutesForDisplayedNights)
                        ConsistencyChartCard(nights: nights)
                        if let correlations = cycleCorrelations {
                            CycleCorrelationCard(correlations: correlations)
                        }
                    }
                }
                .padding()
            }
            .nightBackground()
            .navigationTitle("Insights")
            .zoonGlobalToolbar()
        }
    }

    /// The 7/30-day scope, sitting directly above the charts it scopes.
    ///
    /// It used to be a `.topBarTrailing` toolbar item, which put a full
    /// segmented control in the navigation bar alongside the two global
    /// buttons (Log, More) that every tab carries -- three trailing items
    /// crowded into one bar, visibly cramped in a rendered capture and the
    /// only tab where the bar looked different from the other three.
    ///
    /// Inline is also the more honest placement: the window scopes the chart
    /// section only. The hero and hub above it have their own fixed windows,
    /// so a control in the navigation bar overstated what it changed.
    private var windowPicker: some View {
        Picker("Window", selection: $window) {
            ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var insightsHub: some View {
        VStack(spacing: 8) {
            // Sleep Need, Sleep Debt, Body Clock, and Body Signals moved to
            // `CoreIntelligenceGrid` above -- a 2x2 grid of distinct visuals
            // rather than four more identical rows here.
            hubRow("Cause Finder", icon: AnyView(ZoonIcon.CauseFinder(tint: Theme.Metric.hrv)), Theme.Metric.hrv) { CauseFinderView() }
            hubRow("Sleep Story", "clock.arrow.circlepath", Theme.Metric.sleep) { SleepStoryView() }
            hubRow("Sleep Playbook", "checklist", Theme.Metric.recoveryHigh) { SleepPlaybookView() }
            hubRow("Year in Sleep", "square.grid.3x3.fill", Theme.Metric.recoveryHigh) { YearHeatmapView() }
            hubRow("Labs", "flask", .secondary) { LabsView() }
        }
    }

    private func hubRow<Destination: View>(
        _ title: String, _ symbol: String, _ tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        hubRow(title, icon: AnyView(Image(systemName: symbol).font(Theme.text(15))), tint, destination: destination)
    }

    /// Overload for rows whose concept has its own `ZoonIcon` mark instead
    /// of a generic SF Symbol -- currently only Cause Finder, one of the
    /// redesign spec's named custom-icon concepts.
    private func hubRow<Destination: View>(
        _ title: String, icon: AnyView, _ tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                icon
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(Theme.label(14, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.text(11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .glassCard()
        }
        .buttonStyle(PressableStyle())
    }

    private var notEnoughData: some View {
        ContentUnavailableView {
            Label("Not enough history", systemImage: "chart.xyaxis.line")
        } description: {
            Text("Trends appear once Zoon has recorded a few nights. Keep wearing your watch to bed.")
        }
        .padding(.top, 60)
    }
}

// MARK: - Duration

struct DurationChartCard: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double
    var tagsByDate: [Date: Set<BehaviorTag>] = [:]

    @State private var selectedDate: Date?

    var body: some View {
        ChartCard(
            title: "Sleep Duration",
            subtitle: "Hours asleep vs your \(SleepNightFeatures.formatMinutes(goalMinutes)) goal"
        ) {
            Chart {
                ForEach(nights) { night in
                    BarMark(
                        x: .value("Date", night.date, unit: .day),
                        y: .value("Hours", night.timeAsleepMinutes / 60)
                    )
                    .foregroundStyle(
                        night.timeAsleepMinutes >= goalMinutes
                            ? Color.accentColor
                            : Color.orange.opacity(0.85)
                    )
                    .cornerRadius(3)
                    .opacity(selectedDate == nil
                             || Calendar.current.isDate(night.date, inSameDayAs: selectedDate!) ? 1 : 0.35)
                }

                RuleMark(y: .value("Goal", goalMinutes / 60))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                if let selectedDate, let night = nights.nearest(toDay: selectedDate) {
                    RuleMark(x: .value("Selected", night.date, unit: .day))
                        .foregroundStyle(Theme.neutral(0.25))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ChartSelectionBadge(
                                title: night.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                lines: [
                                    (
                                        "Asleep",
                                        night.formattedTimeAsleep,
                                        night.timeAsleepMinutes >= goalMinutes ? .accentColor : .orange
                                    )
                                ] + loggedLine(for: night.date)
                            )
                        }
                }
            }
            .chartYAxisLabel("hours")
            .chartXSelection(value: $selectedDate)
            // Chart-level summary plus per-mark elements still reachable by
            // swiping in (`.contain`, not `.combine`) -- the redesign spec's
            // "VoiceOver summary" and "selected-point description" for every
            // chart, previously none of them had either.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityValue(selectedPointDescription ?? "")
        }
    }

    private var accessibilitySummary: String {
        guard !nights.isEmpty else { return "Sleep duration chart. No nights in this period." }
        let avgMinutes = nights.reduce(0.0) { $0 + $1.timeAsleepMinutes } / Double(nights.count)
        let metGoal = nights.filter { $0.timeAsleepMinutes >= goalMinutes }.count
        return """
        Sleep duration chart. \(nights.count) nights, averaging \
        \(SleepNightFeatures.formatMinutes(avgMinutes)) against a \
        \(SleepNightFeatures.formatMinutes(goalMinutes)) goal. \
        \(metGoal) of \(nights.count) nights met the goal.
        """
    }

    private var selectedPointDescription: String? {
        guard let selectedDate, let night = nights.nearest(toDay: selectedDate) else { return nil }
        let date = night.date.formatted(.dateTime.weekday(.wide).month().day())
        let met = night.timeAsleepMinutes >= goalMinutes ? "met the goal" : "below the goal"
        return "Selected: \(date), \(night.formattedTimeAsleep) asleep, \(met)."
    }

    /// Sparse by design -- only nights with a journal entry get a second
    /// line, so the badge doesn't imply every night was logged.
    private func loggedLine(for date: Date) -> [(label: String, value: String, tint: Color)] {
        guard let tags = tagsByDate[date], !tags.isEmpty else { return [] }
        let labels = tags.map(\.label).sorted().joined(separator: ", ")
        return [("Logged", labels, Theme.Metric.hrv)]
    }
}

// MARK: - HRV

struct HRVChartCard: View {
    let nights: [SleepNightFeatures]

    @State private var selectedDate: Date?

    private var points: [SleepNightFeatures] {
        nights.filter { $0.avgHRV != nil }
    }

    var body: some View {
        ChartCard(
            title: "Heart Rate Variability",
            subtitle: "Overnight SDNN. Higher generally means better recovery."
        ) {
            if points.count < 2 {
                unavailable
            } else {
                Chart {
                    ForEach(points) { night in
                        LineMark(
                            x: .value("Date", night.date, unit: .day),
                            y: .value("HRV", night.avgHRV ?? 0)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.pink)
                        .symbol(.circle)
                        .symbolSize(28)

                        AreaMark(
                            x: .value("Date", night.date, unit: .day),
                            y: .value("HRV", night.avgHRV ?? 0)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.pink.opacity(0.28), .pink.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    if let average = mean {
                        RuleMark(y: .value("Average", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                    }

                    if let selectedDate, let night = points.nearest(toDay: selectedDate), let hrv = night.avgHRV {
                        RuleMark(x: .value("Selected", night.date, unit: .day))
                            .foregroundStyle(Theme.neutral(0.25))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionBadge(
                                    title: night.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                    lines: [("HRV", "\(Int(hrv.rounded())) ms", .pink)]
                                )
                            }
                    }
                }
                // HRV varies hugely between people, so a zero-based axis wastes
                // most of the plot area and flattens the variation that matters.
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("ms")
                .chartXSelection(value: $selectedDate)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityValue(selectedPointDescription ?? "")
            }
        }
    }

    private var mean: Double? {
        let values = points.compactMap(\.avgHRV)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var accessibilitySummary: String {
        guard let mean, let minValue = points.compactMap(\.avgHRV).min(),
              let maxValue = points.compactMap(\.avgHRV).max() else {
            return "Heart rate variability chart. No readings in this period."
        }
        return """
        Heart rate variability chart. \(points.count) nights, averaging \
        \(Int(mean.rounded())) milliseconds, ranging from \(Int(minValue.rounded())) \
        to \(Int(maxValue.rounded())) milliseconds.
        """
    }

    private var selectedPointDescription: String? {
        guard let selectedDate, let night = points.nearest(toDay: selectedDate), let hrv = night.avgHRV else { return nil }
        let date = night.date.formatted(.dateTime.weekday(.wide).month().day())
        return "Selected: \(date), \(Int(hrv.rounded())) milliseconds."
    }

    private var unavailable: some View {
        Text("No HRV readings in this period. HRV needs an Apple Watch worn overnight.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

// MARK: - Sleep debt

/// Running sleep debt across the window.
///
/// Plots `SleepDebtCalculator.debtSeries` -- the exact same decay recurrence
/// the Sleep Debt screen's headline number comes from, not a second,
/// independent running total. That used to be two different algorithms: this
/// chart previously accumulated `max(0, goal - sleep)` with no decay, which
/// only ever grows, while the Sleep Debt screen showed an exponentially
/// decaying figure that can fall night to night -- so the same user, the same
/// nights, could show two different "Sleep Debt" numbers depending which
/// screen they were on. There is now exactly one implementation of this
/// metric; see `SleepDebtCalculator`.
struct SleepDebtChartCard: View {
    let nights: [SleepNightFeatures]
    /// Debt in minutes as of each night in `nights`, same order and count.
    /// Computed by the caller (`TrendsView`) via `SleepDebtCalculator
    /// .debtSeries` over the *full* stored history, not just this chart's
    /// display window -- a night's debt depends on decayed contributions
    /// from nights before the window starts, so slicing history before
    /// running the decay would understate every point on the chart.
    let debtMinutes: [Double]

    private struct DebtPoint: Identifiable {
        let date: Date
        let hours: Double
        var id: Date { date }
    }

    private var points: [DebtPoint] {
        zip(nights, debtMinutes).map { night, minutes in
            DebtPoint(date: night.date, hours: minutes / 60)
        }
    }

    @State private var selectedDate: Date?

    var body: some View {
        ChartCard(
            title: "Accumulated Sleep Debt",
            subtitle: "Running shortfall across this period. Only short nights add to it."
        ) {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Debt", point.hours)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.orange.opacity(0.4), .orange.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Debt", point.hours)
                    )
                    .foregroundStyle(.orange)
                }

                if let selectedDate,
                   let point = points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                    RuleMark(x: .value("Selected", point.date, unit: .day))
                        .foregroundStyle(Theme.neutral(0.25))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ChartSelectionBadge(
                                title: point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                lines: [("Owed", String(format: "%.1fh", point.hours), .orange)]
                            )
                        }
                }
            }
            .chartYAxisLabel("hours owed")
            .chartXSelection(value: $selectedDate)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityValue(selectedPointDescription ?? "")
        }
    }

    private var accessibilitySummary: String {
        guard let latest = points.last else { return "Accumulated sleep debt chart. No data in this period." }
        let peak = points.map(\.hours).max() ?? latest.hours
        return """
        Accumulated sleep debt chart. Currently \(String(format: "%.1f", latest.hours)) \
        hours owed, peaking at \(String(format: "%.1f", peak)) hours across this period.
        """
    }

    private var selectedPointDescription: String? {
        guard let selectedDate,
              let point = points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) else { return nil }
        let date = point.date.formatted(.dateTime.weekday(.wide).month().day())
        return "Selected: \(date), \(String(format: "%.1f", point.hours)) hours owed."
    }
}

// MARK: - Consistency

/// Bedtime and wake time per night.
///
/// The most useful chart in the app for most people: the *shape* shows schedule
/// drift at a glance, which is a stronger lever on sleep quality than any single
/// night's stage breakdown.
struct ConsistencyChartCard: View {
    let nights: [SleepNightFeatures]

    private struct Point: Identifiable {
        let date: Date
        /// Hours from midnight, shifted so evening bedtimes plot below midnight
        /// as negative values — otherwise 23:30 and 00:30 sit at opposite ends
        /// of the axis and a perfectly steady sleeper looks chaotic.
        let bedHour: Double
        let wakeHour: Double
        var id: Date { date }
    }

    private var points: [Point] {
        let calendar = Calendar.current
        return nights.map { night in
            Point(
                date: night.date,
                bedHour: Self.shiftedHour(of: night.bedtime, calendar: calendar),
                wakeHour: Self.shiftedHour(of: night.wakeTime, calendar: calendar)
            )
        }
    }

    /// Maps a wall-clock time to hours-from-midnight in the range −6…18, so a
    /// night spanning midnight is a continuous vertical span.
    private static func shiftedHour(of date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return hour >= 18 ? hour - 24 : hour
    }

    @State private var selectedDate: Date?

    var body: some View {
        ChartCard(
            title: "Schedule Consistency",
            subtitle: "Bedtime to wake time each night. A steady shape beats a long one."
        ) {
            Chart {
                ForEach(points) { point in
                    RectangleMark(
                        x: .value("Date", point.date, unit: .day),
                        yStart: .value("Bedtime", point.bedHour),
                        yEnd: .value("Wake", point.wakeHour),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.indigo, .blue.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)
                }

                if let selectedDate,
                   let point = points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                    RuleMark(x: .value("Selected", point.date, unit: .day))
                        .foregroundStyle(Theme.neutral(0.25))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ChartSelectionBadge(
                                title: point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                lines: [
                                    ("Bed", Self.clockLabel(point.bedHour), .indigo),
                                    ("Wake", Self.clockLabel(point.wakeHour), .blue)
                                ]
                            )
                        }
                }
            }
            // Explicit Double literals throughout. `-6...12` would infer
            // ClosedRange<Int>, which doesn't match the Double-plottable Y
            // values, and a bare `[-4, -2, ...]` array would infer [Int] —
            // making `value.as(Double.self)` return nil and silently blanking
            // every axis label.
            .chartYScale(domain: -6.0...12.0)
            .chartYAxis {
                AxisMarks(values: [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(Self.clockLabel(hour))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityValue(selectedPointDescription ?? "")
        }
    }

    private static func clockLabel(_ shiftedHour: Double) -> String {
        let hour = Int((shiftedHour < 0 ? shiftedHour + 24 : shiftedHour).rounded())
        return String(format: "%02d:00", hour % 24)
    }

    private var accessibilitySummary: String {
        guard !points.isEmpty else { return "Schedule consistency chart. No nights in this period." }
        return "Schedule consistency chart, showing bedtime to wake time for \(points.count) nights."
    }

    private var selectedPointDescription: String? {
        guard let selectedDate,
              let point = points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) else { return nil }
        let date = point.date.formatted(.dateTime.weekday(.wide).month().day())
        return "Selected: \(date), bed \(Self.clockLabel(point.bedHour)), wake \(Self.clockLabel(point.wakeHour))."
    }
}

// MARK: - Chart shell

/// Consistent titling, padding, and height for every chart.
struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content
                .frame(height: 170)
                .padding(.top, 6)
        }
        .glassCard()
    }
}

// MARK: - Previews

#Preview("Trends") {
    TrendsView()
        .zoonPreviewEnvironment()
}

#Preview("Individual charts") {
    ScrollView {
        VStack(spacing: 16) {
            DurationChartCard(nights: MockData.history, goalMinutes: 480)
            HRVChartCard(nights: MockData.history)
            SleepDebtChartCard(
                nights: MockData.history,
                debtMinutes: SleepDebtCalculator.debtSeries(
                    timeAsleepMinutesOldestFirst: MockData.history.map(\.timeAsleepMinutes),
                    goalMinutes: 480
                )
            )
            ConsistencyChartCard(nights: MockData.recentWeek)
        }
        .padding()
    }
    .nightBackground()
}
