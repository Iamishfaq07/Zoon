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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ZoonStyle.stackSpacing) {
                    if nights.count < 2 {
                        notEnoughData
                    } else {
                        DurationChartCard(nights: nights, goalMinutes: preferences.sleepGoalMinutes)
                        HRVChartCard(nights: nights)
                        SleepDebtChartCard(nights: nights, goalMinutes: preferences.sleepGoalMinutes)
                        ConsistencyChartCard(nights: nights)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Window", selection: $window) {
                        ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
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
                }

                RuleMark(y: .value("Goal", goalMinutes / 60))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYAxisLabel("hours")
        }
    }
}

// MARK: - HRV

struct HRVChartCard: View {
    let nights: [SleepNightFeatures]

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
                }
                // HRV varies hugely between people, so a zero-based axis wastes
                // most of the plot area and flattens the variation that matters.
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("ms")
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

    var body: some View {
        ChartCard(
            title: "Accumulated Sleep Debt",
            subtitle: "Running shortfall across this period. Only short nights add to it."
        ) {
            Chart(points) { point in
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
            .chartYAxisLabel("hours owed")
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

    var body: some View {
        ChartCard(
            title: "Schedule Consistency",
            subtitle: "Bedtime to wake time each night. A steady shape beats a long one."
        ) {
            Chart(points) { point in
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
            .chartYScale(domain: -6...12)
            .chartYAxis {
                AxisMarks(values: [-4, -2, 0, 2, 4, 6, 8]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(Self.clockLabel(hour))
                        }
                    }
                }
            }
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
        .zoonCard()
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
    .background(Color(.systemGroupedBackground))
}
