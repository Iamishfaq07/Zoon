import SwiftUI

/// Zoon Twin as an instrument rather than three sentences: pick a lever and
/// a direction, and the person's real nights split into two groups drawn as
/// two translucent ranges on one axis.
///
/// ```
/// WHAT IF?
///
/// Sleep duration            [ more ⟷ less ]
///
/// HRV
///   Other nights   ░░░░░████████░░░░░
///                           ▏48 ms
///   Longer nights      ░░░░░████████████░░░
///                                ▏54 ms
/// ```
///
/// Two bands per outcome, each spanning where the middle 80% of that group's
/// nights landed, each with a tick at its median. Overlap is the honest
/// picture: two medians 6 ms apart under bands that mostly coincide is a
/// modest tendency, and the drawing says so without a p-value. The bands
/// widen and narrow with the person's own variability, so certainty is
/// visible as shape -- a wide band is a shaky estimate -- and no exact
/// what-if number is ever animated, because `ZoonTwin` does not produce one.
///
/// Switching lever or direction re-splits the same nights and the bands
/// slide to their new positions. That is the only motion here: it shows a
/// change the person just made. Reduce Motion crossfades instead.
///
/// The projections are `ZoonTwin.projectAll` unchanged; this draws what that
/// already computes plus the per-group ranges it now carries.
struct ZoonWhatIfLab: View {
    let nights: [SleepNightFeatures]

    @State private var lever: TrendEngine.Metric = .duration
    @State private var direction: ZoonTwin.Direction = .more
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Levers a person can actually move. HRV and resting heart rate are
    /// outcomes of the night, not choices about it, and sleep debt is a sum
    /// of durations already offered.
    private static let levers: [TrendEngine.Metric] = [.duration, .bedtime, .efficiency]

    private var projections: [ZoonTwin.Projection] {
        Array(ZoonTwin.projectAll(nights: nights, lever: lever, direction: direction).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            controls

            if projections.isEmpty {
                Text("Not enough nights on both sides of this split yet. Zoon needs about \(ZoonTwin.minimumGroupNights.pluralized("night")) with \(direction.word) \(lever.label) and as many without.")
                    .font(Theme.text(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 120, alignment: .topLeading)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(projections) { projection in
                        outcomeRow(projection)
                    }
                }
                .transition(.opacity)

                if let first = projections.first {
                    Text(first.caveat)
                        .font(Theme.evidence)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: lever)
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: direction)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What if?")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            // Lever pills. Native glass because these float over the plot
            // and are the one thing a finger goes to on this screen.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.levers, id: \.self) { candidate in
                        Button {
                            guard candidate != lever else { return }
                            Haptics.select()
                            lever = candidate
                        } label: {
                            ZoonMetricPill(
                                text: leverTitle(candidate),
                                tint: tint(for: candidate),
                                isSelected: candidate == lever
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Split by \(candidate.label)")
                    }
                }
            }

            // Direction is a native segmented control -- no custom switch.
            Picker("Direction", selection: $direction) {
                Text(directionTitle(.more)).tag(ZoonTwin.Direction.more)
                Text(directionTitle(.less)).tag(ZoonTwin.Direction.less)
            }
            .pickerStyle(.segmented)
            .onChange(of: direction) { _, _ in Haptics.select() }
        }
    }

    // MARK: - Outcome row

    /// One outcome, two groups, one axis.
    private func outcomeRow(_ projection: ZoonTwin.Projection) -> some View {
        let outcomeTint = tint(for: projection.outcome)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(projection.outcome.label.capitalizedFirst)
                    .font(Theme.label(14, weight: .semibold))
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: projection.isImprovement ? "arrow.up.right" : "arrow.down.right")
                        .font(Theme.text(9, weight: .bold))
                    Text("\(projection.outcome.formattedMagnitude(abs(projection.delta))) \(projection.isImprovement ? "better" : "worse")")
                        .font(Theme.text(12, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(projection.isImprovement ? Theme.Family.recovery : Theme.Family.attention)
            }

            let axis = sharedAxis(projection)
            VStack(alignment: .leading, spacing: 8) {
                rangeLane(
                    title: "Other nights",
                    count: projection.otherNights,
                    range: projection.otherwiseRange,
                    median: projection.outcomeOtherwise,
                    axis: axis,
                    metric: projection.outcome,
                    tint: Theme.neutral(0.55),
                    emphasised: false
                )
                rangeLane(
                    title: groupTitle,
                    count: projection.leverNights,
                    range: projection.withLeverRange,
                    median: projection.outcomeWithLever,
                    axis: axis,
                    metric: projection.outcome,
                    tint: outcomeTint,
                    emphasised: true
                )
            }

            ZoonEvidenceBadge(confidence: projection.confidence)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(projection.sentence)
        .accessibilityValue(rangeDescription(projection))
    }

    // MARK: - Range lane

    /// Both groups' bands, plus their medians, with a little air either
    /// side so neither band ever touches the edge of the frame.
    private func sharedAxis(_ projection: ZoonTwin.Projection) -> ClosedRange<Double> {
        let low = min(projection.otherwiseRange.lowerBound, projection.withLeverRange.lowerBound,
                      projection.outcomeOtherwise, projection.outcomeWithLever)
        let high = max(projection.otherwiseRange.upperBound, projection.withLeverRange.upperBound,
                       projection.outcomeOtherwise, projection.outcomeWithLever)
        let pad = max((high - low) * 0.12, 1)
        return (low - pad)...(high + pad)
    }

    /// One group as a band on the shared axis: a translucent capsule from
    /// the 10th to the 90th percentile with a tick at the median. The
    /// emphasised lane is the lever group; the other is drawn quieter so
    /// the eye compares the emphasised band against a backdrop rather than
    /// two equals.
    private func rangeLane(
        title: String,
        count: Int,
        range: ClosedRange<Double>,
        median: Double,
        axis: ClosedRange<Double>,
        metric: TrendEngine.Metric,
        tint: Color,
        emphasised: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.supportingLabel)
                    .foregroundStyle(emphasised ? .primary : .secondary)
                Text("· \(count.pluralized("night"))")
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(metric.formattedMagnitude(median))
                    .font(Theme.supportingLabel)
                    .monospacedDigit()
                    .foregroundStyle(emphasised ? tint : .secondary)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let span = axis.upperBound - axis.lowerBound
                let x: (Double) -> CGFloat = { width * CGFloat(($0 - axis.lowerBound) / span) }
                let left = x(range.lowerBound)
                let right = x(range.upperBound)
                let mid = x(median)
                let thickness: CGFloat = emphasised ? 14 : 10

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.neutral(0.10))
                        .frame(height: 1)

                    Capsule()
                        .fill(tint.opacity(emphasised ? 0.28 : 0.18))
                        .overlay(Capsule().strokeBorder(tint.opacity(emphasised ? 0.7 : 0.35), lineWidth: 1))
                        .frame(width: max(right - left, thickness), height: thickness)
                        .offset(x: left)

                    Rectangle()
                        .fill(tint)
                        .frame(width: 2, height: thickness + 6)
                        .offset(x: mid - 1)
                }
                .frame(height: geo.size.height)
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 26 : 20)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Copy

    private var groupTitle: String {
        switch (lever, direction) {
        case (.duration, .more): "Longer nights"
        case (.duration, .less): "Shorter nights"
        case (.bedtime, .more): "Later bedtimes"
        case (.bedtime, .less): "Earlier bedtimes"
        case (.efficiency, .more): "More efficient nights"
        case (.efficiency, .less): "Less efficient nights"
        default: "Nights with \(direction.word) \(lever.label)"
        }
    }

    private func leverTitle(_ metric: TrendEngine.Metric) -> String {
        switch metric {
        case .duration: "Sleep duration"
        case .bedtime: "Bedtime"
        case .efficiency: "Efficiency"
        default: metric.label.capitalizedFirst
        }
    }

    /// Direction words that read correctly for the lever. "Later" and
    /// "earlier" for bedtime, since "more bedtime" is not English.
    private func directionTitle(_ candidate: ZoonTwin.Direction) -> String {
        switch (lever, candidate) {
        case (.bedtime, .more): "Later"
        case (.bedtime, .less): "Earlier"
        case (_, .more): "More"
        case (_, .less): "Less"
        }
    }

    private func tint(for metric: TrendEngine.Metric) -> Color {
        switch metric {
        case .duration, .efficiency, .sleepDebt: Theme.Family.sleep
        case .bedtime: Theme.Family.circadian
        case .hrv: Theme.Family.recovery
        case .restingHeartRate: Theme.Family.bodySignals
        }
    }

    private func rangeDescription(_ projection: ZoonTwin.Projection) -> String {
        let metric = projection.outcome
        return "Other nights ranged \(metric.formattedMagnitude(projection.otherwiseRange.lowerBound)) to \(metric.formattedMagnitude(projection.otherwiseRange.upperBound)). \(groupTitle) ranged \(metric.formattedMagnitude(projection.withLeverRange.lowerBound)) to \(metric.formattedMagnitude(projection.withLeverRange.upperBound)). \(projection.confidence.label)."
    }
}

#Preview("What-if lab") {
    let coordinator = PreviewSupport.coordinator
    ScrollView {
        ZoonWhatIfLab(nights: coordinator.recentNights)
            .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}

#Preview("What-if lab - light, large text") {
    let coordinator = PreviewSupport.coordinator
    ScrollView {
        ZoonWhatIfLab(nights: coordinator.recentNights)
            .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
    .preferredColorScheme(.light)
    .environment(\.dynamicTypeSize, .accessibility2)
}
