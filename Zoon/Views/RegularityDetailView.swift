import SwiftUI

/// Sleep regularity's full detail -- one tap deeper from the Today Health
/// Pulse strip, in place of `RegularityCard` sitting directly on Today.
struct RegularityDetailView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var context: DayContext? { coordinator.state.context }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let context {
                    RegularityCard(regularity: context.regularity)
                } else {
                    ContentUnavailableView("No night yet", systemImage: "moon.zzz")
                        .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Regularity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Regularity Detail") {
    NavigationStack { RegularityDetailView() }
        .zoonPreviewEnvironment()
}
