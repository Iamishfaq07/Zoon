import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)

/// Lock Screen card and Dynamic Island for a running Tonight wind-down.
///
/// Dim on purpose: this is looked at in a dark room at bedtime. The countdown
/// is `Text(timerInterval:)`, animated by the system rather than pushed.
struct WindDownLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindDownActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(red: 0.051, green: 0.063, blue: 0.141))
                .activitySystemActionForegroundColor(tint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Wind down", systemImage: "moon.stars")
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.stageLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: context.attributes.startedAt...context.state.endsAt, countsDown: true)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.attributes.startedAt...context.state.endsAt, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(tint)
                }
            } compactLeading: {
                Image(systemName: "moon.stars")
                    .foregroundStyle(tint)
            } compactTrailing: {
                Text(timerInterval: context.attributes.startedAt...context.state.endsAt, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(tint)
            } minimal: {
                Image(systemName: "moon.stars")
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }

    // Literal colours, as in `NapLiveActivity`: an activity must render the
    // same whether or not the app's asset catalog is loaded. A softer violet
    // than the nap's, because this one is on screen as the lights go out.
    private var tint: Color { Color(red: 0.62, green: 0.56, blue: 0.95) }

    private func lockScreen(_ context: ActivityViewContext<WindDownActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Winding down", systemImage: "moon.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(context.state.stageLabel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Lights out at \(context.state.endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text(timerInterval: context.attributes.startedAt...context.state.endsAt, countsDown: true)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tint)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Winding down, \(context.state.stageLabel). Lights out at \(context.state.endsAt.formatted(date: .omitted, time: .shortened)).")
    }
}

#endif
