import SwiftUI

/// A guided experiment's day-by-day record, one cell per elapsed day:
///
/// ```
/// M  T  W  T  F  S  S
/// ✓  ✓  ×  ✓  ✓  ?  ✓
/// ```
///
/// This is the whole adherence story at a glance -- how long the trial has
/// run, which nights actually followed the plan, which broke it and which
/// were never logged -- where the previous card gave "Logged 5 of 8 days".
/// A ribbon of ticks and crosses is read the way a habit calendar is: the
/// pattern (a bad weekend, a strong second week) is what the eye takes in
/// before it counts anything.
///
/// * Compliance is judged against `direction` the same way
///   `GuidedExperiment` does: `.avoid` counts a `.no` night as compliant,
///   `.pursue` counts a `.yes`. Unlogged nights are `?`, never assumed
///   either way.
/// * Every cell has a distinct symbol as well as a tint, so the ribbon reads
///   without colour. Tapping a cell reveals that day's date and status.
/// * The ribbon has no draw-in of its own: a new day is a new cell, and the
///   only animation is the selected cell settling.
struct ZoonTrialRibbon: View {
    let tag: BehaviorTag
    let startDate: Date
    let direction: GuidedExperiment.Direction
    let observations: [JournalCorrelator.Observation]
    var tint: Color = Theme.Family.sleep
    /// Ceiling on visible cells so a six-week trial doesn't overflow; older
    /// days fall off the left. The count always reflects every day.
    var maxVisibleDays: Int = 21

    @State private var selectedDay: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar

    enum DayStatus: Equatable {
        case compliant, broken, unlogged, upcoming

        var symbol: String {
            switch self {
            case .compliant: "checkmark"
            case .broken: "xmark"
            case .unlogged: "questionmark"
            case .upcoming: "circle.dotted"
            }
        }

        var label: String {
            switch self {
            case .compliant: "followed the plan"
            case .broken: "broke the plan"
            case .unlogged: "not logged"
            case .upcoming: "tonight, not yet"
            }
        }
    }

    struct Day: Identifiable, Equatable {
        let date: Date
        let status: DayStatus
        var id: Date { date }
    }

    // MARK: - Data

    /// Every day from `startDate` through today, in order.
    var days: [Day] {
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: .now)
        guard start <= today else { return [] }
        let byDay = Dictionary(
            observations.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var result: [Day] = []
        var cursor = start
        while cursor <= today {
            let status: DayStatus
            if cursor == today {
                status = .upcoming
            } else if let observation = byDay[cursor] {
                let state = observation.exposureState(for: tag)
                if state == .unknown {
                    status = .unlogged
                } else {
                    status = state == direction.compliantExposureState ? .compliant : .broken
                }
            } else {
                status = .unlogged
            }
            result.append(Day(date: cursor, status: status))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private var visibleDays: [Day] { Array(days.suffix(maxVisibleDays)) }

    private var counts: (compliant: Int, broken: Int, unlogged: Int) {
        let judged = days.filter { $0.status != .upcoming }
        return (
            judged.filter { $0.status == .compliant }.count,
            judged.filter { $0.status == .broken }.count,
            judged.filter { $0.status == .unlogged }.count
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day \(max(days.count, 1))")
                    .font(Theme.supportingValue)
                    .monospacedDigit()
                Spacer()
                Text(summaryLine)
                    .font(Theme.evidence)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            ribbon

            if let selectedDay, let day = days.first(where: { $0.date == selectedDay }) {
                Text("\(day.date.formatted(.dateTime.weekday(.wide).day().month())) · \(day.status.label)")
                    .font(Theme.supportingLabel)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tag.label) experiment, day \(days.count)")
        .accessibilityValue(summaryLine)
    }

    private var summaryLine: String {
        let c = counts
        var parts = [c.compliant.pluralized("night") + " on plan"]
        if c.broken > 0 { parts.append("\(c.broken) off") }
        if c.unlogged > 0 { parts.append("\(c.unlogged) unlogged") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Ribbon

    private var ribbon: some View {
        HStack(spacing: 4) {
            ForEach(visibleDays) { day in
                cell(day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.respecting(reduceMotion, Motion.scrub), value: selectedDay)
    }

    private func cell(_ day: Day) -> some View {
        let isSelected = selectedDay == day.date
        return Button {
            selectedDay = isSelected ? nil : day.date
            Haptics.select()
        } label: {
            VStack(spacing: 4) {
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(Theme.kicker)
                    .foregroundStyle(.tertiary)
                Image(systemName: day.status.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(foreground(day.status))
                    .frame(width: 22, height: 22)
                    .background(background(day.status), in: Circle())
                    .overlay {
                        Circle().strokeBorder(border(day.status), lineWidth: day.status == .upcoming ? 1 : 0)
                    }
                    .scaleEffect(isSelected ? 1.18 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))), \(day.status.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func foreground(_ status: DayStatus) -> Color {
        switch status {
        case .compliant: .white
        case .broken: Theme.Family.attention
        case .unlogged, .upcoming: .secondary
        }
    }

    private func background(_ status: DayStatus) -> Color {
        switch status {
        case .compliant: tint
        case .broken: Theme.Family.attention.opacity(0.16)
        case .unlogged: Theme.neutral(0.08)
        case .upcoming: .clear
        }
    }

    private func border(_ status: DayStatus) -> Color {
        status == .upcoming ? Theme.neutral(0.25) : .clear
    }
}

#Preview("Trial ribbon") {
    let start = Calendar.current.date(byAdding: .day, value: -9, to: .now)!
    return VStack(alignment: .leading, spacing: 24) {
        ZoonTrialRibbon(
            tag: .caffeineLate,
            startDate: start,
            direction: .avoid,
            observations: AppMockData.journalObservations
        )
        ZoonTrialRibbon(
            tag: .readBeforeBed,
            startDate: start,
            direction: .pursue,
            observations: AppMockData.journalObservations,
            tint: Theme.Family.recovery
        )
    }
    .padding()
    .nightBackground()
    .zoonPreviewEnvironment()
}
