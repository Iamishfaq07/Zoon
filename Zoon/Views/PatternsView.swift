import SwiftUI

/// The three engines that describe the shape of someone's nights rather
/// than judging any single one: where their good nights sit, what tends to
/// follow a change, and how predictable tomorrow is.
///
/// Kept off the Today screen deliberately. None of these answer "how did I
/// sleep last night" -- they answer "what are my nights like", which is a
/// question people ask occasionally and with attention, not at a glance
/// before coffee. Putting a nine-region grid on the morning screen would
/// cost the glanceable numbers their prominence and give the grid an
/// audience that isn't looking for it.
struct PatternsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    /// Bedtime against duration, scored on HRV.
    ///
    /// These two axes are the pair someone can actually act on -- both are
    /// choices, where HRV and resting heart rate are outcomes -- and HRV is
    /// the outcome least redundant with the axes themselves. Scoring
    /// duration against a duration axis would report that longer nights are
    /// longer.
    private let mapAxes = (x: TrendEngine.Metric.bedtime, y: TrendEngine.Metric.duration)
    private let mapOutcome = TrendEngine.Metric.hrv

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                forecastSection.entrance(0)
                mapSection.entrance(1)
                twinSection.entrance(2)
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Your patterns")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tomorrow

    @ViewBuilder
    private var forecastSection: some View {
        let forecasts = UncertaintyForecast.forecastAll(nights: coordinator.recentNights)
        if forecasts.isEmpty {
            placeholder("Once there are a couple of weeks of nights, Zoon can say what range tomorrow is likely to land in.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Tomorrow, as a range", "dice", Theme.Metric.strain)

                // Most predictable first, which is what forecastAll already
                // orders by. Capped at three: the ranking exists so the
                // useful ones lead, and a list of six intervals is a table
                // nobody reads.
                ForEach(forecasts.prefix(3), id: \.metric) { forecast in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(forecast.metric.label.capitalizedFirst)
                            .font(Theme.label(14, weight: .semibold))
                        Text(forecast.sentence)
                            .font(Theme.text(12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let first = forecasts.first {
                    Text(first.caveat)
                        .font(Theme.text(11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .glassCard()
        }
    }

    // MARK: - The map

    @ViewBuilder
    private var mapSection: some View {
        if let map = SleepMap.build(
            nights: coordinator.recentNights,
            xAxis: mapAxes.x, yAxis: mapAxes.y, outcome: mapOutcome
        ) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Where your best nights sit", "square.grid.3x3.fill", Theme.Metric.sleep)
                mapGrid(map)
                Text(map.sentence)
                    .font(Theme.text(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(map.caveat)
                    .font(Theme.text(11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        } else {
            placeholder("A month or so of nights, varied enough to split three ways on both bedtime and duration, and a map of them will appear here.")
        }
    }

    /// Rows are duration bands (top = longer), columns are bedtime bands
    /// (left = earlier), so the grid reads like a chart rather than like a
    /// table of the enum's declaration order.
    private func mapGrid(_ map: SleepMap.Map) -> some View {
        VStack(spacing: 4) {
            ForEach([SleepMap.Band.high, .middle, .low], id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach([SleepMap.Band.low, .middle, .high], id: \.self) { column in
                        cell(map.regions.first { $0.x == column && $0.y == row }, in: map)
                    }
                }
            }
            HStack {
                Text(SleepMap.Band.low.phrase(for: mapAxes.x))
                Spacer()
                Text(SleepMap.Band.high.phrase(for: mapAxes.x))
            }
            .font(Theme.text(10))
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func cell(_ region: SleepMap.Region?, in map: SleepMap.Map) -> some View {
        let isBest = region.map { $0.id == map.best?.id } ?? false
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.Metric.sleep.opacity(fill(region, in: map)))
            .frame(height: 44)
            .overlay {
                // An empty region is drawn, not hidden: where someone never
                // sleeps is part of the picture, and a blank cell says that
                // better than a missing one.
                if let region, region.nightCount > 0 {
                    Text("\(region.nightCount)")
                        .font(Theme.text(12, weight: isBest ? .bold : .regular))
                        .foregroundStyle(isBest ? .primary : .secondary)
                }
            }
            .overlay {
                if isBest {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.Metric.recoveryHigh, lineWidth: 2)
                }
            }
    }

    /// Shading tracks how many nights sit in the region, so density reads
    /// before any number does. Unscored regions stay pale whatever their
    /// count, because they carry no outcome to compare.
    private func fill(_ region: SleepMap.Region?, in map: SleepMap.Map) -> Double {
        guard let region, region.nightCount > 0 else { return 0.05 }
        let densest = max(map.regions.map(\.nightCount).max() ?? 1, 1)
        let share = Double(region.nightCount) / Double(densest)
        return region.isScored ? 0.12 + share * 0.33 : 0.08
    }

    // MARK: - What tends to follow

    @ViewBuilder
    private var twinSection: some View {
        let projections = ZoonTwin.projectAll(
            nights: coordinator.recentNights, lever: .duration, direction: .more
        )
        if projections.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("On your longer nights", "arrow.triangle.branch", Theme.Metric.hrv)

                ForEach(projections.prefix(3)) { projection in
                    Text(projection.sentence)
                        .font(Theme.text(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let first = projections.first {
                    Text(first.caveat)
                        .font(Theme.text(11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .glassCard()
        }
    }

    // MARK: - Chrome

    private func sectionHeader(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(Theme.text(13, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.label(13, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Theme.text(13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }
}

#Preview("Your patterns") {
    NavigationStack { PatternsView() }
        .zoonPreviewEnvironment()
}

/// The 3x3 grid is the layout in this app most likely to break at large text:
/// fixed-height rows inside a three-column `HStack`, with a count centred in
/// each cell. Nobody in CI can look at it, so the preview that would show the
/// break is checked in rather than left for someone to configure by hand.
#Preview("Your patterns - large text") {
    NavigationStack { PatternsView() }
        .zoonPreviewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// Light is the appearance the shading and the best-region border were never
/// seen in.
#Preview("Your patterns - light") {
    NavigationStack { PatternsView() }
        .zoonPreviewEnvironment()
        .preferredColorScheme(.light)
}
