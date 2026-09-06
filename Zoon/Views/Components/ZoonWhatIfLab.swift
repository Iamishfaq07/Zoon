import SwiftUI

/// Zoon Twin as an instrument rather than three sentences: pick a lever and
/// a direction, and the person's real nights split into two groups drawn as
/// two translucent ranges on one axis.
///
/// ```
/// COMPARE NIGHTS
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
/// what-if number is ever shown, because `ZoonTwin` does not produce one --
/// which is why this is titled "Compare nights" rather than "What if?".
///
/// Switching lever or direction re-splits the same nights and the bands
/// slide to their new positions. That is the only motion here: it shows a
/// change the person just made. Reduce Motion crossfades instead.
///
/// The bands are `ZoonTwin.projectAll` unchanged, and they are exactly that:
/// a description of the two groups. Above them sits one estimate --
/// `ZoonTwinV2`, matched pairs with a bootstrap interval on a preselected
/// outcome -- which is the only thing on this screen that makes a claim, and
/// which says so when it cannot.
///
/// The bands used to carry a "6 ms better" verdict on each of the top three
/// outcomes, ranked by effect size. That is selection on the result, so the
/// verdict moved up to the matched estimate and the bands now report only how
/// far apart the two medians sit.
struct ZoonWhatIfLab: View {
    let nights: [SleepNightFeatures]

    @State private var lever: TrendEngine.Metric = .duration
    @State private var direction: ZoonTwin.Direction = .more
    /// The matched estimate for the current split, or the reason there is
    /// none. Held in state rather than recomputed in `body`: matching is
    /// quadratic in the number of nights and the interval under it is a
    /// two-thousand-iteration bootstrap, neither of which belongs on a
    /// scroll.
    @State private var matched: ZoonTwinV2.Result?

    /// What a re-estimate depends on. Nights are keyed by count because this
    /// view is handed a window that only ever grows a night at a time.
    private struct MatchKey: Hashable {
        let lever: TrendEngine.Metric
        let direction: ZoonTwin.Direction
        let nights: Int
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Levers a person can actually move -- see `ZoonTwin.levers`, which is
    /// where this list now lives so the evidence ledger records projections
    /// over the same set this screen offers.
    private static let levers: [TrendEngine.Metric] = ZoonTwin.levers

    private var projections: [ZoonTwin.Projection] {
        Array(ZoonTwin.projectAll(nights: nights, lever: lever, direction: direction).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            controls

            matchedSection

            if projections.isEmpty {
                Text("Not enough nights on both sides of this split yet. Zoon needs about \(ZoonTwin.minimumGroupNights.pluralized("night")) with \(direction.word) \(lever.label) and as many without.")
                    .font(Theme.text(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 120, alignment: .topLeading)
                    .transition(.opacity)
            } else {
                // Named so the two halves of this card cannot be confused.
                // Above is one estimate with an interval; this is a
                // description of how the split looked, across several
                // outcomes, and claims nothing.
                Text("How the two groups looked")
                    .font(Theme.kicker)
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

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
        .task(id: MatchKey(lever: lever, direction: direction, nights: nights.count)) {
            let window = nights
            let currentLever = lever
            let currentDirection = direction
            matched = await Task.detached {
                ZoonTwinV2.estimate(nights: window, lever: currentLever, direction: currentDirection)
            }.value
        }
    }

    // MARK: - The matched estimate

    /// The one claim on this screen.
    ///
    /// Everything below it describes how the two groups of nights looked.
    /// This is the only part that estimates a difference, and it does so on
    /// `ZoonTwinV2.preselectedOutcome` alone -- fixed in advance, so the
    /// screen cannot show whichever outcome came out strongest.
    ///
    /// A refusal renders exactly as prominently as an estimate. That is the
    /// point: "Zoon does not have enough comparable nights for this" is the
    /// answer to the question, not a failure to answer it.
    @ViewBuilder
    private var matchedSection: some View {
        switch matched {
        case let .estimated(estimate):
            estimateView(estimate)
        case let .unsupported(reason):
            refusalView(reason)
        case nil:
            EmptyView()
        }
    }

    private func estimateView(_ estimate: ZoonTwinV2.Estimate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Matched comparison")
                    .font(Theme.kicker)
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                ZoonEvidenceBadge(confidence: estimate.confidence)
            }

            Text(estimate.formattedBound(estimate.difference))
                .font(Theme.numeral(28))
                .monospacedDigit()
                .foregroundStyle(verdictTint(estimate))

            Text("\(estimate.outcome.label.capitalizedFirst), range \(estimate.formattedBound(estimate.lower)) to \(estimate.formattedBound(estimate.upper))")
                .font(Theme.text(12))
                .foregroundStyle(.secondary)

            Text(estimate.sentence)
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            matchingDetail(estimate)

            Text(estimate.caveat)
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(estimate.sentence)
    }

    /// Zero is not a direction. An interval spanning it gets the neutral
    /// hue, never the green or amber that would read as a verdict.
    private func verdictTint(_ estimate: ZoonTwinV2.Estimate) -> Color {
        switch estimate.isImprovement {
        case true?: Theme.Family.recovery
        case false?: Theme.Family.attention
        case nil: Theme.neutral(0.70)
        }
    }

    /// How the pairs were made, closed by default.
    ///
    /// Includes the nights matching had to throw away. A comparison built
    /// from twelve of a possible thirty nights is a different thing from one
    /// built from twenty-eight, and only showing the twelve would hide that.
    private func matchingDetail(_ estimate: ZoonTwinV2.Estimate) -> some View {
        DisclosureGroup("How these nights were paired") {
            VStack(alignment: .leading, spacing: 6) {
                detailRow("Pairs used", "\(estimate.pairs)")
                detailRow(
                    "Nights with no close match",
                    estimate.nightsDropped == 0 ? "None" : "\(estimate.nightsDropped) of \(estimate.candidateNights)"
                )
                ForEach(estimate.balance) { balance in
                    detailRow(
                        "Difference left in \(balance.metric.label)",
                        String(format: "%.2f SD", abs(balance.standardisedDifference))
                    )
                }
                Text("Each night was paired with a night of the same day shape and a similar setup, from a similar stretch of your history. Pairs further apart than Zoon's limit were not made at all.")
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
        .font(Theme.label(12, weight: .medium))
        .tint(Theme.Family.sleep)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.evidence)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func refusalView(_ reason: ZoonTwinV2.Unsupported) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Not enough to estimate this", systemImage: "questionmark.circle")
                .font(Theme.label(13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(reason.message)
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if reason.improvesWithMoreNights {
                Text("More nights may change this.")
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Compare nights", not "What if?". The V9 spec reserves
            // counterfactual phrasing for a Twin that matches on
            // confounders; this one splits on a single lever, and the
            // heading was the only place in this feature still promising
            // more than that. Everything under it already said the honest
            // thing -- "on your N nights with later bedtimes…" -- so the
            // title was overselling its own contents.
            Text("Compare nights")
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
                // Says how far apart the two medians sit, and no longer says
                // "better" or "worse". These rows are the top three outcomes
                // ranked by effect size, so a verdict here is a verdict on
                // whichever outcome came out strongest -- selection on the
                // result, and the most reliable way to turn noise into a
                // finding. The verdict is made once, above, on an outcome
                // fixed in advance.
                HStack(spacing: 4) {
                    Image(systemName: projection.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(Theme.text(9, weight: .bold))
                    Text("\(projection.outcome.formattedMagnitude(abs(projection.delta))) apart")
                        .font(Theme.text(12, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
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

#Preview("Compare nights") {
    let coordinator = PreviewSupport.coordinator
    ScrollView {
        ZoonWhatIfLab(nights: coordinator.recentNights)
            .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}

#Preview("Compare nights - light, large text") {
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
