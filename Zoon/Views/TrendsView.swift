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
                    insightsHub

                    if nights.count < 2 {
                        notEnoughData
                    } else {
                        DurationChartCard(nights: nights, goalMinutes: preferences.sleepGoalMinutes, tagsByDate: tagsByDate)
                        HRVChartCard(nights: nights)
                        SleepDebtChartCard(nights: nights, goalMinutes: preferences.sleepGoalMinutes)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Window", selection: $window) {
                        ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .zoonGlobalToolbar()
        }
    }

    private var insightsHub: some View {
        VStack(spacing: 8) {
            hubRow("Sleep Need", "target", Theme.Metric.sleep) { SleepNeedView() }
            hubRow("Sleep Debt", "chart.line.downtrend.xyaxis", Theme.Metric.temperature) { SleepDebtView() }
            hubRow("Body Clock", "clock", Theme.Metric.battery) { BodyClockView() }
            hubRow("Body Signals", "dot.radiowaves.left.and.right", Theme.Metric.recoveryMid) { HealthRadarView() }
            hubRow("Cause Finder", "sparkle.magnifyingglass", Theme.Metric.hrv) { CauseFinderView() }
            hubRow("Year in Sleep", "square.grid.3x3.fill", Theme.Metric.recoveryHigh) { YearHeatmapView() }
            hubRow("Labs", "flask", .secondary) { LabsView() }
        }
    }

    private func hubRow<Destination: View>(
        _ title: String, _ symbol: String, _ tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(Theme.text(15))
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
        }
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
            }
        }
    }

    private var mean: Double? {
        let values = points.compactMap(\.avgHRV)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
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
/// Recomputed here as a running total rather than plotting each night's stored
/// 14-day figure: the stored value is a trailing window that slides, so charting
/// it produces a line that moves for reasons unrelated to how you slept.
struct SleepDebtChartCard: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double

    private struct DebtPoint: Identifiable {
        let date: Date
        let hours: Double
        var id: Date { date }
    }

    private var points: [DebtPoint] {
        var running = 0.0
        return nights.map { night in
            running += max(0, goalMinutes - night.timeAsleepMinutes)
            return DebtPoint(date: night.date, hours: running / 60)
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
        }
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
        }
    }

    private static func clockLabel(_ shiftedHour: Double) -> String {
        let hour = Int((shiftedHour < 0 ? shiftedHour + 24 : shiftedHour).rounded())
        return String(format: "%02d:00", hour % 24)
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
            SleepDebtChartCard(nights: MockData.history, goalMinutes: 480)
            ConsistencyChartCard(nights: MockData.recentWeek)
        }
        .padding()
    }
    .nightBackground()
}
