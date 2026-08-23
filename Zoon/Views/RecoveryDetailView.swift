import SwiftUI

/// Recovery's full working -- what drove it, plus this week's HRV status.
///
/// One tap deeper from the Today Health Pulse strip. Both cards used to sit
/// directly on Today; moving them here is what lets Today read in ten
/// seconds instead of scrolling past a full diagnostic panel every morning.
struct RecoveryDetailView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var context: DayContext? { coordinator.state.context }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let context {
                    RecoveryBreakdownCard(recovery: context.recovery)
                    HRVStatusCard(status: context.hrvStatus)
                } else {
                    ContentUnavailableView("No night yet", systemImage: "moon.zzz")
                        .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Recovery Detail") {
    NavigationStack { RecoveryDetailView() }
        .zoonPreviewEnvironment()
}
