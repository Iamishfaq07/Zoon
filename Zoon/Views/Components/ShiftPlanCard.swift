import SwiftUI

/// The next shift and the windows the schedule leaves around it.
///
/// Drawn as a timeline rather than as a list of times, because the thing worth
/// seeing is the *shape* — where the sleep sits relative to the shift, and
/// whether it is one block or two. A person working nights already knows what
/// time their shift starts; what they cannot see at a glance is that the
/// caffeine cutoff lands in the middle of it.
///
/// **Nothing here grades the shift.** No fatigue figure, no verdict about
/// working it. `ShiftPlan.bannedPositioning` lists the words this must never
/// reach for and the tests hold the engine's copy to them; this view adds no
/// sentences of its own beyond the window titles.
struct ShiftPlanCard: View {

    let plan: ShiftPlan.Plan

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The span the timeline covers: the whole plan, end to end.
    private var span: DateInterval? {
        guard let first = plan.windows.map(\.start).min(),
              let last = plan.windows.map(\.end).max(),
              last > first
        else { return nil }
        return DateInterval(start: first, end: last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: plan.shift.label ?? "Your next shift",
                subtitle: plan.kind.label,
                systemImage: "calendar.badge.clock"
            )

            Text(plan.sentence)
                .font(Theme.text(15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            // The bars are the whole point at ordinary sizes and unreadable at
            // accessibility ones, where four labelled tracks cannot fit a
            // phone's width. The rows below carry every figure the bars do.
            if !dynamicTypeSize.isAccessibilitySize, let span {
                timeline(span)
            }

            VStack(spacing: 8) {
                ForEach(plan.windows) { window in
                    row(window)
                }
            }

            if let cutoff = plan.caffeineCutoff {
                fixedPoint(
                    "Caffeine cutoff",
                    value: cutoff.formatted(.dateTime.hour().minute()),
                    systemImage: "cup.and.saucer"
                )
            }

            if let wake = plan.wakeTarget {
                fixedPoint(
                    "Wake target",
                    value: wake.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                    systemImage: "alarm"
                )
            }

            Text(plan.caveat)
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func timeline(_ span: DateInterval) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.neutral(0.06))
                    .frame(height: 10)

                ForEach(plan.windows) { window in
                    let offset = window.start.timeIntervalSince(span.start) / span.duration
                    let width = (window.end.timeIntervalSince(window.start)) / span.duration
                    Capsule()
                        .fill(tint(window.role))
                        .frame(width: max(3, geo.size.width * width), height: 10)
                        .offset(x: geo.size.width * offset)
                }
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func row(_ window: ShiftPlan.Window) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(tint(window.role))
                .frame(width: 7, height: 7)
            Text(window.title)
                .font(Theme.label(13, weight: .semibold))
            Spacer(minLength: 8)
            Text(range(window))
                .font(Theme.numeral(13))
                .foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func fixedPoint(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkTertiary)
            Text(title)
                .font(Theme.label(13))
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.numeral(13))
        }
        .accessibilityElement(children: .combine)
    }

    private func range(_ window: ShiftPlan.Window) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(window.start.formatted(style))–\(window.end.formatted(style))"
    }

    private func tint(_ role: ShiftPlan.Window.Role) -> Color {
        switch role {
        case .shift: Theme.Metric.strain
        case .preShiftSleep, .postShiftSleep: Theme.Metric.sleep
        case .nap: Theme.Metric.sleep.opacity(0.55)
        }
    }
}
