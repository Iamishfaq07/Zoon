import SwiftUI

/// Travel Mode: a schedule for moving the measured body clock across time
/// zones.
///
/// Reached from Body Clock rather than from the tab bar, on purpose. The plan
/// is expressed entirely in terms of the clock that screen draws -- it is
/// that feature under travel conditions, not a separate one, and burying it
/// behind its own tab would make it look like a second opinion about the same
/// person.
struct TravelPlanView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    /// Simple or detailed. The V9 spec asks for both explicitly here, which
    /// is worth distinguishing from the Basic/Advanced toggle it forbids
    /// elsewhere: those were two depths of the same screen, and this is one
    /// schedule shown either collapsed or day by day. Nothing is hidden in
    /// the simple form -- the preparation steps are summarised into a line
    /// that still says how many days, rather than truncated.
    @State private var detailed = false
    @State private var destination = TimeZone.current
    @State private var departure = Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now
    @State private var arrival = Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now

    private var bodyClock: BodyClock? { coordinator.state.context?.bodyClock }

    private var trip: TravelPlan.Trip {
        TravelPlan.Trip(
            origin: .current,
            destination: destination,
            departure: departure,
            arrival: arrival
        )
    }

    /// Every zone the system knows, ordered so scrolling to one is possible.
    private var zones: [TimeZone] {
        TimeZone.knownTimeZoneIdentifiers.sorted().compactMap(TimeZone.init(identifier:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                tripCard
                if let bodyClock {
                    planSection(bodyClock: bodyClock)
                } else {
                    ContentUnavailableView(
                        "Building your body clock",
                        systemImage: "clock",
                        description: Text("A travel plan is built around your own sleep timing, so Zoon needs \(BodyClock.minimumNights) nights before it can make one.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Travel")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The trip

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your trip", systemImage: "airplane")

            Picker("Destination", selection: $destination) {
                ForEach(zones, id: \.identifier) { zone in
                    Text(zone.identifier.replacingOccurrences(of: "_", with: " "))
                        .tag(zone)
                }
            }
            .pickerStyle(.navigationLink)

            DatePicker("Departure", selection: $departure)
                .onChange(of: departure) { _, new in
                    // An arrival before departure is a plan for a flight that
                    // lands before it takes off, and the shift is measured at
                    // arrival -- so keep the pair ordered rather than letting
                    // the arithmetic run on nonsense.
                    if arrival < new { arrival = new }
                }
            DatePicker("Arrival", selection: $arrival, in: departure...)
        }
        .glassCard()
    }

    // MARK: - The plan

    @ViewBuilder
    private func planSection(bodyClock: BodyClock) -> some View {
        if let plan = TravelPlan.plan(for: trip, bodyClock: bodyClock) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Travel plan", systemImage: "list.bullet")
                    Spacer()
                    Picker("Detail", selection: $detailed) {
                        Text("Simple").tag(false)
                        Text("Detailed").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                Text(headline(for: plan))
                    .font(Theme.text(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(detailed ? plan.steps : plan.simpleSteps) { step in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.when)
                                .font(Theme.label(11, weight: .semibold))
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .foregroundStyle(Theme.Family.circadian)
                            Text(step.action)
                                .font(Theme.text(14))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(caveats(for: plan), id: \.self) { caveat in
                        Text(caveat)
                            .font(Theme.evidence)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .glassCard()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Travel plan", systemImage: "list.bullet")
                Text(noPlanReason)
                    .font(Theme.text(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        }
    }

    /// `TravelPlan.plan` returns nil for a trip not worth planning, and nil
    /// on its own does not say why -- so the direction is asked separately
    /// rather than showing an empty card.
    private var noPlanReason: String {
        switch TravelPlan.direction(for: trip) {
        case .negligible:
            return "Your destination is within \(Int(TravelPlan.negligibleShiftHours)) hours of home. "
                + "That is a late night, not a time-zone problem — Zoon has nothing to shift."
        case .eastward, .westward:
            return "Zoon could not build a plan for this trip."
        }
    }

    private func headline(for plan: TravelPlan.Plan) -> String {
        let hours = abs(plan.shiftHours)
        let rendered = hours == hours.rounded()
            ? String(Int(hours))
            : String(format: "%.1f", hours)
        let noun = hours == 1 ? "hour" : "hours"
        return plan.direction == .eastward
            ? "\(rendered) \(noun) ahead. Your clock has to move earlier, which is the harder direction."
            : "\(rendered) \(noun) behind. Your clock has to move later, which is the easier direction."
    }

    private func caveats(for plan: TravelPlan.Plan) -> [String] {
        [plan.lightCaveat, plan.estimateCaveat, plan.rateCaveat].compactMap { $0 }
    }
}

#Preview("Travel") {
    NavigationStack { TravelPlanView() }
        .zoonPreviewEnvironment()
}
