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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The charts start closed. See `noticedSection`.
    @State private var showsData = false

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
                noticedSection.entrance(0)

                Button {
                    Haptics.select()
                    withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                        showsData.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(showsData ? "Hide the data" : "Explore the data")
                        Image(systemName: showsData ? "chevron.up" : "chevron.down")
                            .font(Theme.text(10, weight: .semibold))
                    }
                    .font(Theme.label(13, weight: .semibold))
                    .foregroundStyle(Theme.Family.sleep)
                }
                .buttonStyle(.plain)
                .entrance(1)

                if showsData {
                    constellationSection.entrance(1)
                    tomorrowSection.entrance(2)
                    forecastSection.entrance(2)
                    mapSection.entrance(2)
                    twinSection.entrance(3)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Your patterns")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Strongest evidence first.
    ///
    /// `JournalCorrelator.Confidence` is a String-raw enum, so sorting on
    /// `rawValue` orders them alphabetically -- high, low, moderate -- which
    /// looks like a sort and is not one. This is the explicit order.
    private static func rank(_ confidence: JournalCorrelator.Confidence) -> Int {
        switch confidence {
        case .high: 2
        case .moderate: 1
        case .low: 0
        }
    }

    // MARK: - Things Zoon has noticed

    /// The findings as sentences, before any visualisation of them.
    ///
    /// Everything below this used to be the whole screen: a constellation
    /// graph, a forecast band, a 3x3 outcome grid, a twin. Each is a good
    /// answer to a narrow question and all four are visualisations -- which
    /// means the first thing the screen asked of someone was to read a chart
    /// and work out the finding for themselves.
    ///
    /// The findings already existed; only their presentation was technical.
    /// `JournalCorrelator` computes matched-pair comparisons with bootstrap
    /// intervals, and `Finding.plainSentence` says what one of them found.
    /// The charts are still here, one tap away, for the reader who wants to
    /// check the working -- which is the point of keeping them.
    @ViewBuilder
    private var noticedSection: some View {
        let findings = JournalCorrelator()
            .topFindingPerTag(from: coordinator.journalObservations())
            .sorted { Self.rank($0.confidence) > Self.rank($1.confidence) }

        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Things Zoon has noticed", "sparkles", Theme.Family.sleep)

            if findings.isEmpty {
                Text("Nothing yet. Log what you did on a few more nights and Zoon can start comparing them against each other.")
                    .font(Theme.text(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                    if index > 0 {
                        Divider().overlay(Theme.neutral(0.10))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.tag.label)
                            .font(Theme.label(14, weight: .semibold))
                        Text(finding.plainSentence)
                            .font(Theme.text(13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // The count is never hidden. A finding from 6 matched
                        // nights and one from 60 read identically without it.
                        Text(finding.supportLine)
                            .font(Theme.evidence)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Connections

    /// What Zoon has connected to your sleep, as a graph rather than a list
    /// of sentences. Leads the screen because it is the one visual here that
    /// answers "what affects me" at a glance; the ranges and the grid below
    /// answer narrower questions.
    @ViewBuilder
    private var constellationSection: some View {
        let findings = JournalCorrelator().topFindingPerTag(from: coordinator.journalObservations())
        if let graph = ZoonConstellation.fromFindings(findings) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("What connects to your sleep", "point.3.filled.connected.trianglepath.dotted", Theme.Family.sleep)
                ZoonConstellation(nodes: graph.nodes, edges: graph.edges, initialFocus: "sleep")
                Text("Tap a connection to see the evidence behind it.")
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Recent range

    @ViewBuilder
    private var forecastSection: some View {
        let forecasts = UncertaintyForecast.forecastAll(nights: coordinator.recentNights)
        if forecasts.isEmpty {
            placeholder("Once there are a couple of weeks of nights, Zoon can show the range yours typically fall in.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // Not "Tonight" or "Tomorrow" -- see `UncertaintyForecast`
                // and the same note in `TonightWidget`. The range is where
                // recent nights landed; naming a night turns it into the
                // prediction the type refuses to make.
                sectionHeader("Your recent range", "dice", Theme.Family.sleep)

                // Most predictable first, which is what forecastAll already
                // orders by. The leader is drawn as a band -- its width is
                // the point -- and the next two are one line each. Capped at
                // three: the ranking exists so the useful ones lead, and a
                // list of six intervals is a table nobody reads.
                if let lead = forecasts.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lead.metric.label.capitalizedFirst)
                            .font(Theme.label(14, weight: .semibold))
                        ZoonUncertaintyBand(forecast: lead, tint: tint(for: lead.metric))
                    }
                }

                if forecasts.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(forecasts.dropFirst().prefix(2), id: \.metric) { forecast in
                            HStack(alignment: .firstTextBaseline) {
                                Text(forecast.metric.label.capitalizedFirst)
                                    .font(Theme.text(13))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text("\(forecast.metric.formattedMagnitude(forecast.lower))–\(forecast.metric.formattedMagnitude(forecast.upper))")
                                    .font(Theme.text(13, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(tint(for: forecast.metric))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(forecast.sentence)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .glassCard()
        }
    }

    // MARK: - Tomorrow, conditioned

    /// The Recent Range narrowed by what tomorrow actually looks like.
    ///
    /// Sits above the range rather than replacing it, and only when it has
    /// something the range does not. When `ContextForecast` falls back --
    /// tomorrow resembles nothing in the history -- this renders nothing at
    /// all, because a "forecast" that is the recent range under a different
    /// heading is the range shown twice.
    @ViewBuilder
    private var tomorrowSection: some View {
        let nights = coordinator.recentNights
        let metric = TrendEngine.Metric.duration
        let samples = ContextForecast.samples(from: nights) { metric.value(from: $0) }

        if let latest = nights.max(by: { $0.date < $1.date }),
           let prediction = ContextForecast.predict(
               for: .describing(latest, previous: previousNight(before: latest, in: nights)),
               from: samples
           ),
           prediction.basis.isConditioned {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Tomorrow, if it looks like tonight", "sparkles", Theme.Family.sleep)

                Text(prediction.rangeLabel(format: metric.formattedMagnitude))
                    .font(Theme.numeral(30))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: metric))

                HStack(spacing: 6) {
                    Text(metric.label.capitalizedFirst)
                    Text("·")
                    Text(prediction.confidence.label)
                }
                .font(Theme.text(12))
                .foregroundStyle(.secondary)

                Text(prediction.sentence(format: metric.formattedMagnitude))
                    .font(Theme.text(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(prediction.caveat)
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(metric.label) tomorrow, \(prediction.rangeLabel(format: metric.formattedMagnitude)), "
                + prediction.confidence.label
            )
        }
    }

    /// The night immediately before `night`, when there is one -- what
    /// `ContextForecast.Context` needs and cannot work out for itself.
    private func previousNight(
        before night: SleepNightFeatures,
        in nights: [SleepNightFeatures]
    ) -> SleepNightFeatures? {
        nights.filter { $0.date < night.date }.max { $0.date < $1.date }
    }

    /// Each metric keeps the hue its family owns everywhere else in the app.
    private func tint(for metric: TrendEngine.Metric) -> Color {
        switch metric {
        case .duration, .efficiency, .sleepDebt: Theme.Family.sleep
        case .bedtime: Theme.Family.circadian
        case .hrv: Theme.Family.recovery
        case .restingHeartRate: Theme.Family.bodySignals
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

    /// Zoon Twin as the what-if lab: lever pills, a direction control, and
    /// two ranges per outcome on one axis. Shown whenever there is any
    /// history at all -- the lab explains its own thresholds when a split
    /// has too few nights on one side, which the old fixed "longer nights"
    /// paragraph could only do by disappearing.
    @ViewBuilder
    private var twinSection: some View {
        if coordinator.recentNights.count >= ZoonTwin.minimumGroupNights * 2 {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("What tends to follow", "arrow.triangle.branch", Theme.Family.recovery)
                ZoonWhatIfLab(nights: coordinator.recentNights)
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
