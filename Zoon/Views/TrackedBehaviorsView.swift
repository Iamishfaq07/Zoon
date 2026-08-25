import SwiftUI

/// Lets the user narrow the Journal's daily quick-confirm list down from
/// the full ~22-tag `BehaviorTag` set to just the handful they actually
/// want asked about every day.
///
/// Nothing here changes what Cause Finder or a Guided Experiment can look
/// for -- narrowing this list only changes what the Journal *prompts* for.
/// A tag switched off here can still be logged by hand if it ever comes up
/// (the full set stays reachable), and switching it back on is a tap away.
struct TrackedBehaviorsView: View {

    @Environment(UserPreferences.self) private var preferences

    private var isCustomized: Bool {
        preferences.trackedBehaviorTagIdentifiers != nil
    }

    var body: some View {
        List {
            Section {
            } footer: {
                Text(isCustomized
                    ? "Showing your chosen set. Turn everything back on to return to the default."
                    : "Everything is currently tracked -- turn any of these off to narrow the daily list.")
            }

            ForEach(BehaviorTag.Category.allCases) { category in
                Section(category.label) {
                    ForEach(category.tags) { tag in
                        Toggle(isOn: Binding(
                            get: { preferences.isTracked(tag) },
                            set: { preferences.setTracked(tag, tracked: $0) }
                        )) {
                            Label(tag.label, systemImage: tag.symbol)
                        }
                    }
                }
            }

            if isCustomized {
                Section {
                    Button("Track Everything") {
                        preferences.resetTrackedBehaviors()
                    }
                }
            }
        }
        .navigationTitle("Tracked Behaviours")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TrackedBehaviorsView()
    }
    .zoonPreviewEnvironment()
}
