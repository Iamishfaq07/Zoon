import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)

/// Lock Screen card and Dynamic Island presentation for a running nap.
///
/// Every countdown here is rendered with `Text(timerInterval:)` rather than a
/// value the app pushes. That's the whole trick: the system animates the
/// remaining time locally, so a twenty-minute nap costs one activity update
/// instead of 1,200 — and Live Activity updates are rate-limited, so the naive
/// approach would be throttled into uselessness anyway.
struct NapLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NapActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(red: 0.051, green: 0.063, blue: 0.141))
                .activitySystemActionForegroundColor(Color(red: 0.482, green: 0.380, blue: 1.0))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Nap", systemImage: "powersleep")
                        .font(.caption)
                        .foregroundStyle(napTint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.attributes.targetMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: context.attributes.startedAt...context.state.endsAt,
                         countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(napTint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        timerInterval: context.attributes.startedAt...context.state.endsAt,
                        countsDown: false
                    ) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(napTint)
                }
            } compactLeading: {
                Image(systemName: "powersleep")
                    .foregroundStyle(napTint)
            } compactTrailing: {
                Text(timerInterval: context.attributes.startedAt...context.state.endsAt,
                     countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(napTint)
            } minimal: {
                Image(systemName: "powersleep")
                    .foregroundStyle(napTint)
            }
            .keylineTint(napTint)
        }
    }

    // Colours are literals rather than Theme references: this file is compiled
    // into the widget extension, and a Live Activity must render identically
    // whether or not the app's asset catalog is loaded.
    private var napTint: Color { Color(red: 0.482, green: 0.380, blue: 1.0) }

    private func lockScreen(_ context: ActivityViewContext<NapActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Napping", systemImage: "powersleep")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(napTint)

                Text(timerInterval: context.attributes.startedAt...context.state.endsAt,
                     countsDown: true)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("\(context.attributes.targetMinutes) minute nap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView(
                timerInterval: context.attributes.startedAt...context.state.endsAt,
                countsDown: false
            ) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "moon.zzz.fill")
                    .font(Theme.text(15))
                    .foregroundStyle(napTint)
            }
            .progressViewStyle(.circular)
            .tint(napTint)
            .frame(width: 54, height: 54)
        }
        .padding(16)
    }
}

#Preview("Nap Live Activity", as: .content, using: NapActivityAttributes(
    targetMinutes: 20,
    startedAt: .now.addingTimeInterval(-480)
)) {
    NapLiveActivity()
} contentStates: {
    NapActivityAttributes.ContentState(
        endsAt: .now.addingTimeInterval(720),
        progress: 0.4
    )
}

#endif
