import SwiftUI

/// Travel Sleep Guidance: a schedule for moving the measured body clock
/// across time zones.
///
/// Named guidance rather than a mode, deliberately. The plan is two rules of
/// thumb and the arithmetic of two time zones; "mode" would imply Zoon
/// switches into a travel-specific understanding of the person, and it does
/// not.
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
    @State private var setup = PersonalSetupStore.shared
    @State private var detailed = false
    @State private var origin = TimeZone.current
    @State private var destination = TimeZone.current
    @State private var departure = Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now
    @State private var arrival = Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now

    private var bodyClock: BodyClock? { coordinator.state.context?.bodyClock }

    private var trip: TravelPlan.Trip {
        TravelPlan.Trip(
            origin: origin,
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
            CascadeStack(alignment: .leading, spacing: Theme.stackSpacing) {
                tripCard
                // The picked origin, not the phone's zone: saved again after
                // landing, that would be the destination.
                Button("Save this trip") {
                    setup.value.trip = .init(
                        destination: destination.identifier, departure: departure, arrival: arrival,
                        origin: origin.identifier
                    )
                }
                NavigationLink { SavedSleepPlansView() } label: { Label("Choose sleep times for this trip", systemImage: "calendar") }
                if let bodyClock {
                    planSection(bodyClock: bodyClock)
                } else {
                    GatheringNights(
                        title: "Building your body clock",
                        message: "A travel plan is built around your own sleep timing, so Zoon needs \(BodyClock.minimumNights) nights before it can make one.",
                        nights: coordinator.recentNights.count,
                        needed: BodyClock.minimumNights
                    )
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .nightBackground()
        .onAppear {
            if let trip = setup.value.trip {
                origin = trip.origin.flatMap(TimeZone.init(identifier:)) ?? .current
                destination = TimeZone(identifier: trip.destination) ?? .current
                departure = trip.departure; arrival = trip.arrival
            }
        }
        // "Travel Sleep Guidance", not "Travel Mode". The V10 spec asks for
        // the honest name until the model is phase-aware, and it is right:
        // the plan is a schedule built from two rules of thumb and the
        // arithmetic of two time zones. "Mode" implies the app switches into
        // a different, travel-specific understanding of the person. It does
        // not -- it gives guidance, from the same body clock as always.
        .navigationTitle("Travel Sleep Guidance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The trip

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your trip", systemImage: "airplane")

            Picker("From", selection: $origin) {
                ForEach(zones, id: \.identifier) { zone in
                    Text(zone.identifier.replacingOccurrences(of: "_", with: " "))
                        .tag(zone)
                }
            }
            .pickerStyle(.navigationLink)

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
                    .adaptiveSegmentedStyle()
                    .frame(width: 170)
                }

                shiftBadge(plan)

                // The steps as a path: a node per step, joined, so the plan
                // reads as a sequence before any of it is read as words.
                let steps = detailed ? plan.steps : plan.simpleSteps
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(Theme.label(11, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Family.circadian)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.Family.circadian.opacity(0.16), in: Circle())
                                if index < steps.count - 1 {
                                    Capsule()
                                        .fill(Theme.Family.circadian.opacity(0.3))
                                        .frame(width: 2)
                                        .frame(minHeight: 10, maxHeight: .infinity)
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.when)
                                    .font(Theme.label(11, weight: .semibold))
                                    .textCase(.uppercase)
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.Family.circadian)
                                Text(step.action)
                                    .font(Theme.text(14))
                            }
                            .padding(.bottom, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .glassCard()

            let notes = caveats(for: plan)
            if !notes.isEmpty {
                ExplainDisclosure(title: "Good to know", lines: notes, systemImage: "info.circle")
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Travel plan", systemImage: "list.bullet")
                Text(noPlanReason)
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
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
            return "Under \(Int(TravelPlan.negligibleShiftHours)) hours from home. That's a late night, not jet lag."
        case .eastward, .westward:
            return "Zoon could not build a plan for this trip."
        }
    }

    /// The shift as one big signed number and which way the clock moves,
    /// in place of a sentence that said the same.
    private func shiftBadge(_ plan: TravelPlan.Plan) -> some View {
        let east = plan.direction == .eastward
        let hours = abs(plan.shiftHours)
        let rendered = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return HStack(spacing: 14) {
            Image(systemName: east ? "sunrise.fill" : "sunset.fill")
                .font(Theme.text(22, weight: .semibold))
                .foregroundStyle(Theme.Family.circadian)
                .frame(width: 52, height: 52)
                .background(Theme.Family.circadian.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(east ? "+" : "−")\(rendered)h")
                    .font(Theme.numeral(30))
                    .monospacedDigit()
                Text(east ? "Clock moves earlier · the harder way" : "Clock moves later · the easier way")
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline(for: plan))
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

#Preview("Travel Sleep Guidance") {
    NavigationStack { TravelPlanView() }
        .zoonPreviewEnvironment()
}
