import SwiftUI

/// A year of recovery at a glance, GitHub-contribution-graph style.
///
/// Nothing else in the app shows more than about 30 days at once, so a
/// seasonal pattern -- worse sleep every winter, a rough stretch that lines up
/// with a specific month -- has nowhere to become visible. This is the one
/// screen built to be looked at from a distance, not read number by number.
struct YearHeatmapView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedDate: Date?

    private let daysBack = 364
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    private var weeks: [[Date]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        // Align to the previous Sunday so every column is a complete week --
        // otherwise the first partial week would render shorter than the rest.
        let startWeekday = calendar.component(.weekday, from: rangeStart)
        guard let alignedStart = calendar.date(byAdding: .day, value: -(startWeekday - 1), to: rangeStart) else { return [] }

        var days: [Date] = []
        var day = alignedStart
        while day <= today {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // Pad the trailing week out to a full 7 so the grid stays rectangular.
        let endWeekday = calendar.component(.weekday, from: today)
        for _ in 0..<(7 - endWeekday) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: days[days.count - 1]) else { break }
            days.append(next)
        }

        return stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    private var selectedRecovery: Int? {
        selectedDate.flatMap { coordinator.recoveryHistory[$0] }
    }

    private var selectedNight: SleepNightFeatures? {
        guard let selectedDate else { return nil }
        return coordinator.recentNights.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                summaryCard.entrance(0)
                gridCard.entrance(1)
                if let selectedDate {
                    detailCard(for: selectedDate)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                legendCard.entrance(2)
            }
            .padding()
            .animation(reduceMotion ? nil : Motion.value, value: selectedDate)
        }
        .nightBackground()
        .navigationTitle("Year in Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let values = coordinator.recoveryHistory.values
        let average = values.isEmpty ? nil : values.reduce(0, +) / values.count
        let trackedDays = values.count

        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(average.map { "\($0)%" } ?? "--")
                    .font(Theme.numeral(30))
                    .monospacedDigit()
                    .foregroundStyle(average.map { Theme.recoveryColor(Double($0)) } ?? .secondary)
                Text("Average recovery")
                    .font(Theme.text(10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(trackedDays)")
                    .font(Theme.numeral(30))
                    .monospacedDigit()
                Text("Nights tracked")
                    .font(Theme.text(10))
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    // MARK: - Grid

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Last 12 Months", systemImage: "square.grid.3x3.fill")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                            VStack(spacing: cellSpacing) {
                                monthLabel(for: week, previousWeek: index > 0 ? weeks[index - 1] : nil)
                                ForEach(week, id: \.self) { day in
                                    cell(for: day)
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    // Land on today rather than the start of the year --
                    // that's the end someone actually wants to look at first.
                    proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                }
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func monthLabel(for week: [Date], previousWeek: [Date]?) -> some View {
        let calendar = Calendar.current
        let isNewMonth = previousWeek.map {
            !calendar.isDate($0[0], equalTo: week[0], toGranularity: .month)
        } ?? true

        Text(isNewMonth ? week[0].formatted(.dateTime.month(.abbreviated)) : "")
            .font(Theme.text(8, weight: .semibold))
            .foregroundStyle(.tertiary)
            // The fixed height is structural -- every column's label slot has
            // to be the same height or the heatmap grid below it stops
            // lining up -- but `Theme.text` maps to a text *style*, so it
            // scales with Dynamic Type and an 8pt label clips out of a 12pt
            // slot at the larger sizes. Shrinking inside the slot keeps both
            // the alignment and the label.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: 12)
    }

    private func cell(for day: Date) -> some View {
        let calendar = Calendar.current
        let isFuture = day > calendar.startOfDay(for: .now)
        let recovery = coordinator.recoveryHistory[day]
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: recovery, isFuture: isFuture))
            .frame(width: cellSize, height: cellSize)
            .scaleEffect(isSelected ? 1.35 : 1)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.white, lineWidth: 1.5)
                }
            }
            .animation(reduceMotion ? nil : Motion.tap, value: isSelected)
            .onTapGesture {
                guard !isFuture else { return }
                Haptics.select()
                selectedDate = calendar.isDate(selectedDate ?? .distantPast, inSameDayAs: day) ? nil : day
            }
    }

    private func color(for recovery: Int?, isFuture: Bool) -> Color {
        guard !isFuture else { return .clear }
        guard let recovery else { return Theme.neutral(0.06) }
        return Theme.recoveryColor(Double(recovery)).opacity(0.35 + 0.65 * (Double(recovery) / 100))
    }

    // MARK: - Detail

    private func detailCard(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Theme.label(13, weight: .semibold))
                Spacer()
                if let selectedRecovery {
                    Text("\(selectedRecovery)% recovery")
                        .font(Theme.label(13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.recoveryColor(Double(selectedRecovery)))
                } else {
                    Text("No data")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
            }
            if let selectedNight {
                NavigationLink {
                    PastNightDetailView(night: selectedNight)
                } label: {
                    HStack {
                        Text("View that night")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Legend

    private var legendCard: some View {
        HStack(spacing: 6) {
            Text("Lower")
                .font(Theme.text(9))
                .foregroundStyle(.tertiary)
            ForEach([10, 30, 50, 70, 90], id: \.self) { value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(for: value, isFuture: false))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("Higher")
                .font(Theme.text(9))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

#Preview("Year Heatmap") {
    NavigationStack { YearHeatmapView() }
        .zoonPreviewEnvironment()
}
