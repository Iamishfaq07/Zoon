import SwiftUI

/// Banner for an active `RecoveryMode` -- auto-suggested from last night's
/// recovery band, or manually turned on. Shown near the top of Today,
/// alongside the other "what should I do today" signals.
struct RecoveryModeCard: View {
    let mode: RecoveryMode
    let onTurnOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Theme.Metric.recoveryMid)
                    .frame(width: 24, height: 24)
                    .background(Theme.Metric.recoveryMid.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.headline)
                        .font(Theme.label(14, weight: .semibold))
                    Text(mode.detail)
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if mode.isDismissible {
                Button("Turn off for today", action: onTurnOff)
                    .font(Theme.text(11, weight: .semibold))
                    .foregroundStyle(Theme.Metric.recoveryMid)
            }
        }
        .glassCard()
    }
}

/// Small always-available affordance to turn Recovery Mode on manually,
/// shown only when it isn't already active -- vitals lag reality, so this
/// exists for the days that don't show up in HRV yet.
struct RecoveryModeEnableLink: View {
    let onEnable: () -> Void

    var body: some View {
        Button {
            onEnable()
        } label: {
            Label("Not feeling recovered? Turn on Recovery Mode", systemImage: "leaf")
                .font(Theme.text(11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Recovery Mode") {
    VStack(spacing: 16) {
        RecoveryModeCard(mode: RecoveryMode(source: .autoSuggested), onTurnOff: {})
        RecoveryModeCard(mode: RecoveryMode(source: .manuallyEnabled), onTurnOff: {})
        RecoveryModeEnableLink(onEnable: {})
    }
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}
