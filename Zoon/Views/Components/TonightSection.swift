import SwiftUI

/// Tonight as one connected timeline, on the page.
///
/// Folds three former Today cards into one sequence: `BedtimeCountdownCard`
/// becomes the header line ("Bed in 4h 12m"), `TonightTimelineCard`'s nodes
/// become the vertical spine, and `AutopilotCard`'s recommendation becomes
/// the detail on the Bed node -- so the plan and the adjustment to it read
/// as one thing, which they are.
///
/// Every time comes from where it always did: the target bedtime from
/// `DayContext.targetBedtime()` (the same value the reminder is scheduled
/// against), wind-down from `BedtimeReminder.windDownLeadMinutes`, the
/// caffeine cutoff from `CaffeineCutoff.time(bedtime:)`, wake from
/// `BodyClock.window(for:)`, and the shift from `SleepAutopilot.plan`.
struct TonightSection: View {
    let context: DayContext
    let autopilot: SleepAutopilot.Plan?
    var now: Date = .now

    @Environment(UserPreferences.self) private var preferences

    private var bedtime: Date? { context.targetBedtime(now: now) }

    private var nodes: [ZoonTimeline.Node] {
        guard let bedtime else { return [] }
        var result: [ZoonTimeline.Node] = []

        if let cutoff = CaffeineCutoff.time(bedtime: bedtime, now: now) {
            result.append(.init(
                id: "caffeine", time: cutoff, title: "Caffeine cutoff",
                detail: "A general guideline, about \(Int(CaffeineCutoff.leadHours))h before bed",
                symbol: "cup.and.saucer.fill", tint: Theme.Metric.strain
            ))
        }

        result.append(.init(
            id: "windDown",
            time: bedtime.addingTimeInterval(-Double(BedtimeReminder.windDownLeadMinutes) * 60),
            title: "Wind down",
            symbol: "moon.haze.fill", tint: Theme.Family.circadian
        ))

        result.append(.init(
            id: "bed", time: bedtime, title: "Bed",
            detail: bedDetail,
            symbol: "bed.double.fill", tint: Theme.Family.sleep,
            isEmphasised: autopilot.map { !$0.isHolding } ?? false
        ))

        if let latency = context.night.sleepLatencyMinutes, latency > 2 {
            result.append(.init(
                id: "asleep", time: bedtime.addingTimeInterval(latency * 60), title: "Target asleep",
                detail: "Based on your usual \(Int(latency.rounded()))m to fall asleep",
                symbol: "zzz", tint: Theme.Family.sleep
            ))
        }

        if let wake = context.bodyClock?.window(for: now)?.end {
            result.append(.init(id: "wake", time: wake, title: "Wake", symbol: "sunrise.fill", tint: Theme.Metric.battery))
        }
        return result
    }

    /// The autopilot's sentence, or the plain need when there is no plan yet.
    private var bedDetail: String? {
        if let autopilot {
            return autopilot.isHolding
                ? "Your usual time works tonight"
                : autopilot.sentence
        }
        return "For \(SleepNightFeatures.formatMinutes(context.sleepNeed.totalNeedMinutes)) of sleep"
    }

    var body: some View {
        if let bedtime, !nodes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ZoonSectionHeader(preferences.isShiftWorkModeEnabled ? "Next sleep" : "Tonight") {
                    countdown(to: bedtime)
                }
                ZoonTimeline(nodes: nodes, now: now)
                if let autopilot {
                    Text(autopilot.caveat)
                        .font(Theme.text(11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Bed in 4h 12m" / "Bedtime was 22:45" -- the countdown that used to be
    /// a whole card.
    private func countdown(to bedtime: Date) -> some View {
        let remaining = bedtime.timeIntervalSince(now)
        return Group {
            if remaining > 60 {
                Text("Bed in \(SleepNightFeatures.formatMinutes(remaining / 60))")
            } else if remaining > -3 * 3600 {
                Text("Bedtime now")
            } else {
                Text("Bedtime was \(bedtime, format: .dateTime.hour().minute())")
            }
        }
        .font(Theme.label(12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Theme.Family.sleep)
        .contentTransition(.numericText())
    }
}

#Preview("Tonight") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 32) {
                TonightSection(
                    context: AppMockData.dayContext(),
                    autopilot: SleepAutopilot.Plan(
                        targetBedtimeMinutes: -20, targetSleepMinutes: 480, shiftMinutes: -20,
                        debtRepaymentMinutes: 30, isHolding: false, confidence: .moderate
                    )
                )
                TonightSection(context: AppMockData.dayContext(), autopilot: nil)
            }
            .padding()
        }
        .nightBackground()
    }
    .zoonPreviewEnvironment()
}
