import SwiftUI

/// A glance at Zoon's four standing status domains, each a tap from its own
/// full detail screen.
///
/// Redesign spec's "Health Pulse" ask: exactly four categories -- Recovery,
/// Body Signals, Breathing, Regularity -- each with a visual distinct enough
/// that the row doesn't read as four identical tiles. Before this, it showed
/// all seven `VitalsStatus.Kind` readings (RHR, HRV, respiratory rate, SpO2,
/// wrist temp, sleep duration, breathing disturbances) with one shared
/// icon+value template -- a second, denser vitals list rather than the
/// four-domain glance the spec actually asks for. Tapping through used to
/// mean scrolling Today's own full-detail cards (`RecoveryBreakdownCard`,
/// `VitalsCard`, `HRVStatusCard`, `RegularityCard`) -- now those (`VitalsCard`
/// folded into `HealthRadarView`'s own baseline rows) live one tap deeper,
/// off Today entirely.
struct HealthPulseStrip: View {
    let context: DayContext
    /// For `BreathingHealth.compute` -- the same call `BreathingHealthView`
    /// itself makes, so the two can never disagree about tonight's pattern.
    let recentNights: [SleepNightFeatures]

    private var breathing: BreathingHealth { BreathingHealth.compute(nights: recentNights) }

    var body: some View {
        HStack(spacing: 0) {
            tile(recoveryTile)
            Spacer(minLength: 4)
            tile(bodySignalsTile)
            Spacer(minLength: 4)
            tile(breathingTile)
            Spacer(minLength: 4)
            tile(regularityTile)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .glassCard(padding: 0)
    }

    @ViewBuilder
    private func tile(_ content: some View) -> some View {
        content.frame(maxWidth: .infinity)
    }

    // MARK: - Recovery -- a small ring, the same visual grammar as the score itself.

    private var recoveryTile: some View {
        NavigationLink {
            RecoveryDetailView()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().stroke(Theme.neutral(0.10), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: Double(context.recovery.percent) / 100)
                        .stroke(Theme.recoveryColor(Double(context.recovery.percent)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)
                pulseLabel("Recovery", value: "\(context.recovery.percent)")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery")
        .accessibilityValue("\(context.recovery.percent) percent, \(context.recovery.band.label)")
        .accessibilityHint("View recovery breakdown")
    }

    // MARK: - Body Signals -- a small dot cluster, one per drifting vital.

    private var bodySignalsTile: some View {
        let radar = context.healthRadar
        let tint: Color = radar.isActive
            ? (radar.severity == .notable ? Theme.Metric.recoveryLow : Theme.Metric.recoveryMid)
            : Theme.Metric.recoveryHigh

        return NavigationLink {
            HealthRadarView()
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index < radar.signals.count ? tint : Theme.neutral(0.12))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 22)
                pulseLabel("Signals", value: radar.isActive ? "\(radar.signals.count)" : "OK")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body Signals")
        .accessibilityValue(radar.isActive ? "\(radar.signals.count) signals drifting" : "Nothing unusual")
        .accessibilityHint("View body signals")
    }

    // MARK: - Breathing -- a small three-bar waveform.

    private var breathingTile: some View {
        let tint: Color = {
            switch breathing.pattern {
            case .insufficientData: .secondary
            case .normal: Theme.Metric.recoveryHigh
            case .repeatedPattern: Theme.Metric.recoveryMid
            }
        }()

        return NavigationLink {
            BreathingHealthView()
        } label: {
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach([10.0, 16.0, 12.0], id: \.self) { height in
                        Capsule().fill(tint).frame(width: 3, height: height)
                    }
                }
                .frame(height: 22)
                pulseLabel("Breathing", value: breathingValueLabel)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Breathing")
        .accessibilityValue(breathing.pattern.label)
        .accessibilityHint("View breathing health")
    }

    private var breathingValueLabel: String {
        switch breathing.pattern {
        case .insufficientData: "--"
        case .normal: "OK"
        case let .repeatedPattern(nightsElevated, _): "\(nightsElevated)n"
        }
    }

    // MARK: - Regularity -- a small horizontal index gauge.

    private var regularityTile: some View {
        let regularity = context.regularity
        let tint: Color = {
            switch regularity.band {
            case .exemplary: Theme.Metric.recoveryHigh
            case .consistent: Theme.Metric.battery
            case .variable: Theme.Metric.recoveryMid
            case .erratic: Theme.Metric.recoveryLow
            }
        }()

        return NavigationLink {
            RegularityDetailView()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.neutral(0.10)).frame(height: 4)
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * max(0.04, min(1, regularity.index / 100)), height: 4)
                    }
                    .frame(height: 4)
                }
                .frame(width: 30, height: 22)
                pulseLabel("Rhythm", value: "\(Int(regularity.index))")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Regularity")
        .accessibilityValue("\(Int(regularity.index)), \(regularity.band.label)")
        .accessibilityHint("View sleep regularity")
    }

    private func pulseLabel(_ title: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(Theme.label(12, weight: .semibold))
                .monospacedDigit()
            Text(title)
                .font(Theme.text(9))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Health Pulse") {
    HealthPulseStrip(context: AppMockData.dayContext(), recentNights: MockData.history)
        .padding()
        .zoonPreviewEnvironment()
}

/// The four tiles divide the width evenly and each carries a label under its
/// own visual, so this is the row where large text runs out of horizontal
/// room first.
#Preview("Health Pulse - large text") {
    HealthPulseStrip(context: AppMockData.dayContext(), recentNights: MockData.history)
        .padding()
        .zoonPreviewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// A poor day, because three of the four tiles are colour-coded against
/// thresholds and the good-day preview only ever exercises one side of them.
#Preview("Health Pulse - poor day") {
    HealthPulseStrip(context: AppMockData.poorDayContext(), recentNights: MockData.history)
        .padding()
        .zoonPreviewEnvironment()
}
