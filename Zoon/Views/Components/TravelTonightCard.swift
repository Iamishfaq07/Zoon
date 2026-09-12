import SwiftUI

/// Shows a saved trip on evening/night Today so Tonight and the jet-lag plan
/// cannot disagree by living in different rooms.
struct TravelTonightCard: View {
    @State private var setup = PersonalSetupStore.shared

    var body: some View {
        if let trip = setup.value.trip, isActive(trip) {
            NavigationLink {
                TravelPlanView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Travel")
                        .font(Theme.kicker)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(destinationName(trip.destination))
                        .font(Theme.label(20, weight: .semibold))
                    Text("Destination nights move \(Int(SleepAutopilot.maximumNightlyShift)) minutes at a time, so Tonight and this plan cannot disagree.")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open travel plan")
        }
    }

    private func isActive(_ trip: PersonalSetup.SavedTrip) -> Bool {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -4, to: trip.departure) ?? trip.departure
        let end = calendar.date(byAdding: .day, value: 3, to: trip.arrival) ?? trip.arrival
        return Date.now >= start && Date.now <= end
    }

    private func destinationName(_ identifier: String) -> String {
        identifier.split(separator: "/").last?.replacingOccurrences(of: "_", with: " ") ?? identifier
    }
}
