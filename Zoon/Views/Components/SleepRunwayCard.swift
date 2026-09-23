import SwiftUI

/// The next seven mornings as stacked opportunity bars, against the need
/// each one has to cover.
///
/// Horizon language, the same metaphor Tonight and Tomorrow use: time runs
/// left to right, the need is a mark on the track, and the bar is how much
/// room the schedule leaves. A day the bar falls short of the mark is the
/// whole point of the screen, and it is visible as a length before any word
/// is read.
///
/// Selecting a day reveals why — which is the difference between a chart and
/// a decoration.
struct SleepRunwayCard: View {

    let plan: SleepRunway.Plan
    @State private var selected: Date?
    @State private var setup = PersonalSetupStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Every bar is measured against the same ceiling so the days are
    /// comparable to each other, not each to itself.
    private var scale: Double {
        max(
            plan.days.map(\.needMinutes).max() ?? 480,
            plan.days.map(\.opportunityMinutes).max() ?? 480
        )
    }

    private var selectedDay: SleepRunway.Day? {
        plan.days.first { $0.date == selected } ?? plan.firstShortDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "7-day sleep runway",
                subtitle: "Where the week stops leaving room for the sleep you need.",
                systemImage: "calendar.day.timeline.left"
            )

            Text(plan.sentence)
                .font(Theme.text(15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 8) {
                ForEach(plan.days) { day in
                    row(day)
                }
            }

            if let day = selectedDay {
                detail(day)
            }

            LabeledContent("Confidence", value: plan.confidence.label)
                .font(Theme.text(12))

            if !plan.usedCalendar {
                Text("No calendar commitments are feeding this. It is built from your own habit and any morning time you set.")
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(plan.caveat)
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    /// One morning. The bar is the opportunity; the tick is the need.
    private func row(_ day: SleepRunway.Day) -> some View {
        Button {
            selected = day.date
            Haptics.select()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(Theme.label(12, weight: .semibold))
                        .foregroundStyle(day.isShort ? Theme.Metric.strain : Theme.inkSecondary)
                    Spacer(minLength: 6)
                    Text(SleepNightFeatures.formatMinutes(day.opportunityMinutes))
                        .font(Theme.numeral(14))
                        .monospacedDigit()
                    // Never colour alone: a short day carries its own
                    // signed number and a glyph, so it separates in
                    // greyscale and for VoiceOver.
                    if day.isShort {
                        Label(
                            "−\(SleepNightFeatures.formatMinutes(day.gapMinutes))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Theme.Metric.strain)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    track(day)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(day))
        .accessibilityHint("Shows why this morning looks like this.")
        .accessibilityAddTraits(day.date == selectedDay?.date ? [.isSelected, .isButton] : .isButton)
    }

    private func track(_ day: SleepRunway.Day) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.neutral(0.08))
                Capsule()
                    .fill(day.isShort ? Theme.Metric.strain.opacity(0.75) : Theme.Metric.sleep)
                    .frame(width: width * min(1, day.opportunityMinutes / scale))
                // The need, as a mark on the same track. A bar short of it is
                // the finding.
                Rectangle()
                    .fill(Theme.inkSecondary)
                    .frame(width: 1.5, height: 12)
                    .offset(x: width * min(1, day.needMinutes / scale) - 0.75)
            }
        }
        .frame(height: 12)
    }

    private func detail(_ day: SleepRunway.Day) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                .font(Theme.label(12, weight: .semibold))
            Text("Wake \(clock(day.wake)) · \(day.wakeSource.label). Bed by \(clock(day.bedtime)) leaves \(SleepNightFeatures.formatMinutes(day.opportunityMinutes)) against a need of \(SleepNightFeatures.formatMinutes(day.needMinutes)).")
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Why, not only that: the thing that pins this night, named by
            // what it is and how movable it is. See `ScheduleFriction`.
            if let why = ScheduleFriction.read(day: day).explanation {
                Text("Main constraint: \(why)")
                    .font(Theme.text(12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Skipping a night stops its reminders and alarm without
            // deleting any plan, and says so.
            Toggle(isOn: Binding(
                get: { !setup.value.isSkipped(wake: day.wake) },
                set: { setup.value.setSkipped(!$0, wake: day.wake) }
            )) {
                Text("Reminders for this night")
                    .font(Theme.text(12))
            }
            .tint(Theme.Metric.sleep)
            if setup.value.isSkipped(wake: day.wake) {
                Text("Skipped: no bedtime reminder, wake window or alarm will be set for this night.")
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.neutral(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func accessibilityLabel(_ day: SleepRunway.Day) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        let opportunity = SleepNightFeatures.formatMinutes(day.opportunityMinutes)
        guard day.isShort else {
            return "\(weekday). \(opportunity) of sleep opportunity, enough for your need."
        }
        return "\(weekday). \(opportunity) of sleep opportunity, \(SleepNightFeatures.formatMinutes(day.gapMinutes)) short of your need."
    }
}
