import SwiftUI

/// The four standing analytical modules -- Sleep Need, Sleep Debt, Body
/// Clock, Body Signals -- as a 2x2 grid of distinct visuals, not four rows
/// of the same icon+label+chevron template.
///
/// Redesign spec's "Core Intelligence" ask. Before this, all nine Insights
/// hub entries (these four plus Cause Finder, Sleep Story, Sleep Playbook,
/// Year in Sleep, Labs) rendered through one shared `hubRow` -- visually
/// indistinguishable from a Settings list. These four are the ones the spec
/// singles out for their own 2x2 module treatment; the rest stay as list
/// rows below, since findings-style presentation for Cause Finder/
/// Experiments/Playbook is a separate piece of work.
struct CoreIntelligenceGrid: View {
    let context: DayContext

    /// Shared with each tile's destination view so the push animation can
    /// zoom outward from the tapped tile instead of the generic slide-in --
    /// the redesign spec's ask for these four modules specifically.
    @Namespace private var zoom

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            sleepNeedTile
            sleepDebtTile
            bodyClockTile
            bodySignalsTile
        }
    }

    // MARK: - Sleep Need -- a horizontal fill bar, achieved against need.

    private var sleepNeedTile: some View {
        let need = max(context.sleepNeed.totalNeedMinutes, 1)
        let achieved = context.night.total24hAsleepMinutes
        let fraction = min(1, achieved / need)

        return module(
            title: "Sleep Need",
            icon: AnyView(ZoonIcon.SleepNeed(tint: Theme.Metric.sleep, fraction: fraction)),
            tint: Theme.Metric.sleep, zoomID: "sleepNeed"
        ) {
            SleepNeedView(zoomNamespace: zoom, zoomID: "sleepNeed")
        } visual: {
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.neutral(0.10)).frame(height: 6)
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.Metric.sleep)
                        .frame(width: geo.size.width * max(0.03, fraction), height: 6)
                }
                .frame(height: 6)
            }
        } stat: {
            "\(SleepNightFeatures.formatMinutes(achieved)) of \(SleepNightFeatures.formatMinutes(need))"
        }
    }

    // MARK: - Sleep Debt -- a filled arc gauge.

    private var sleepDebtTile: some View {
        let debt = context.night.sleepDebtMinutes ?? 0
        // Debt beyond about 5 hours reads as "full" on the gauge -- past
        // that point the exact figure matters more than the fill amount,
        // and the number below the gauge still carries it precisely.
        let fraction = min(1, debt / 300)

        return module(
            title: "Sleep Debt",
            icon: AnyView(ZoonIcon.SleepDebt(tint: Theme.Metric.temperature, deficit: fraction)),
            tint: Theme.Metric.temperature, zoomID: "sleepDebt"
        ) {
            SleepDebtView(zoomNamespace: zoom, zoomID: "sleepDebt")
        } visual: {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(Theme.neutral(0.10), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(180))
                Circle()
                    .trim(from: 0, to: 0.5 * fraction)
                    .stroke(Theme.Metric.temperature, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(180))
            }
            .frame(height: 20)
        } stat: {
            debt < 1 ? "Clear" : "\(SleepNightFeatures.formatMinutes(debt)) owed"
        }
    }

    // MARK: - Body Clock -- a position dot on a ring.

    private var bodyClockTile: some View {
        let bodyClock = context.bodyClock
        // Habitual midpoint, hours from midnight (evening negative) -- see
        // `BodyClock.midpoint`'s own doc comment -- mapped to an angle around
        // a 24-hour ring, midnight at the top.
        let angle: Double = {
            guard let midpoint = bodyClock?.midpoint else { return -90 }
            let hourOfDay = midpoint < 0 ? midpoint + 24 : midpoint
            return hourOfDay / 24 * 360 - 90
        }()

        return module(
            title: "Body Clock",
            icon: AnyView(ZoonIcon.BodyClock(tint: Theme.Metric.battery)),
            tint: Theme.Metric.battery, zoomID: "bodyClock"
        ) {
            BodyClockView(zoomNamespace: zoom, zoomID: "bodyClock")
        } visual: {
            ZStack {
                Circle().stroke(Theme.neutral(0.10), lineWidth: 2)
                Circle()
                    .fill(Theme.Metric.battery)
                    .frame(width: 6, height: 6)
                    .offset(x: 10)
                    .rotationEffect(.degrees(angle))
            }
            .frame(height: 20)
        } stat: {
            bodyClock.map { $0.stability.label } ?? "Building"
        }
    }

    // MARK: - Body Signals -- a dot cluster, one per drifting vital.

    private var bodySignalsTile: some View {
        let radar = context.healthRadar
        let tint: Color = radar.isActive
            ? (radar.severity == .notable ? Theme.Metric.recoveryLow : Theme.Metric.recoveryMid)
            : Theme.Metric.recoveryHigh

        return module(
            title: "Body Signals",
            icon: AnyView(ZoonIcon.BodySignals(tint: Theme.Metric.recoveryMid)),
            tint: Theme.Metric.recoveryMid, zoomID: "bodySignals"
        ) {
            HealthRadarView(zoomNamespace: zoom, zoomID: "bodySignals")
        } visual: {
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < radar.signals.count ? tint : Theme.neutral(0.12))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 20)
        } stat: {
            radar.isActive ? "\(radar.signals.count) drifting" : "Nothing unusual"
        }
    }

    // MARK: - Shared module shell

    private func module<Destination: View, Visual: View>(
        title: String,
        icon: AnyView,
        tint: Color,
        zoomID: String,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder visual: () -> Visual,
        stat: () -> String
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    icon
                        .frame(width: 13, height: 13)
                    Text(title)
                        .font(Theme.label(12, weight: .semibold))
                    Spacer(minLength: 0)
                }
                visual()
                Text(stat())
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 0)
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: zoomID, in: zoom)
    }
}

#Preview("Core Intelligence Grid") {
    NavigationStack {
        ScrollView {
            CoreIntelligenceGrid(context: AppMockData.poorDayContext())
                .padding()
        }
        .nightBackground()
    }
    .zoonPreviewEnvironment()
}
