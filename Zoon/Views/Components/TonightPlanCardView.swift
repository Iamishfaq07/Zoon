import SwiftUI

/// Tonight's plan as a connected timeline: wind down, bed, wake.
///
/// The three times were already computed and were previously printed as a
/// row of labels. A row says three facts; a line through them says they are
/// one evening, in order, with distances between them — which is the thing
/// someone is actually reading off it at eleven at night.
struct TonightPlanCardView: View {

    struct Step: Identifiable {
        enum Kind { case windDown, bed, wake }

        let kind: Kind
        let time: Date
        /// Shown under the step. `nil` for the steps that need no gloss.
        var note: String?

        var id: String { title }

        var title: String {
            switch kind {
            case .windDown: "Wind down"
            case .bed: "Bed"
            case .wake: "Wake"
            }
        }

        var symbol: String {
            switch kind {
            case .windDown: "moon.stars.fill"
            case .bed: "bed.double.fill"
            case .wake: "sun.horizon.fill"
            }
        }

        var tint: Color {
            switch kind {
            case .windDown: Theme.Family.bodySignals
            case .bed: Theme.Family.sleep
            case .wake: Theme.Family.circadian
            }
        }
    }

    let steps: [Step]
    /// Tonight's target time asleep.
    let targetMinutes: Double
    /// When the first step is still ahead, how long until it.
    var bedIn: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    row(step, isLast: index == steps.count - 1)
                }
            }
        }
        .glassCard()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tonight's plan")
                    .font(Theme.label(16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Target \(SleepNightFeatures.formatMinutes(targetMinutes))")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 8)

            if let bedIn, bedIn > 60 {
                Text("Bed in \(SleepNightFeatures.formatMinutes(bedIn / 60))")
                    .font(Theme.label(12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Family.sleep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.Family.sleep.opacity(0.14), in: Capsule())
            }
        }
    }

    /// One step: its node, the connector down to the next, and its text.
    ///
    /// The connector is drawn by the row above rather than as a single line
    /// behind the stack, so it stops at the last node instead of running off
    /// the bottom of the card — and so a row that grows (a note wrapping onto
    /// three lines) lengthens its own connector rather than leaving a gap.
    private func row(_ step: Step, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(step.tint.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(step.tint.opacity(0.35), lineWidth: 1)
                        .frame(width: 34, height: 34)
                    Image(systemName: step.symbol)
                        .font(Theme.text(14, weight: .semibold))
                        .foregroundStyle(step.tint)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }

                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [step.tint.opacity(0.35), Theme.neutral(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title)
                        .font(Theme.label(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text(step.time, format: .dateTime.hour().minute())
                        .font(Theme.label(14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(step.tint)
                }

                if let note = step.note {
                    Text(note)
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(step.title) at \(step.time.formatted(date: .omitted, time: .shortened))"
                + (step.note.map { ". \($0)" } ?? "")
        )
    }
}

#Preview("Tonight's plan") {
    ZStack {
        Theme.background.ignoresSafeArea()
        TonightPlanCardView(
            steps: [
                .init(kind: .windDown, time: .now.addingTimeInterval(3600 * 4)),
                .init(
                    kind: .bed,
                    time: .now.addingTimeInterval(3600 * 4.5),
                    note: "30 minutes earlier than usual, to start clearing tonight's shortfall."
                ),
                .init(kind: .wake, time: .now.addingTimeInterval(3600 * 15))
            ],
            targetMinutes: 588,
            bedIn: 3600 * 4
        )
        .padding()
    }
    .zoonPreviewEnvironment()
}
