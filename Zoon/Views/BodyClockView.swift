import SwiftUI

/// The signature 24-hour circadian visualization — your estimated preferred
/// sleep window laid against what actually happened last night, on one ring.
struct BodyClockView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    /// Set only when pushed from `CoreIntelligenceGrid`'s tile -- see
    /// `SleepNeedView`'s doc comment on the same pair of properties.
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    /// One selection shared by the dial and the list below it: dragging the
    /// dial highlights a moment, tapping a moment moves the dial.
    @State private var inspectedFraction: Double?
    @State private var showingMethod = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bodyClock: BodyClock? { coordinator.state.context?.bodyClock }
    private var night: SleepNightFeatures? { coordinator.state.context?.night }

    var body: some View {
        // `.zoom(...)` and `.automatic` are different concrete types
        // conforming to `NavigationTransition`, so branching the transition
        // value itself (e.g. via a ternary) doesn't type-check -- branching
        // the view instead lets each branch's `.navigationTransition(_:)`
        // call resolve its own concrete opaque type independently.
        if let zoomNamespace, let zoomID {
            content.navigationTransition(.zoom(sourceID: zoomID, in: zoomNamespace))
        } else {
            content.navigationTransition(.automatic)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let bodyClock, let night {
                    ring(bodyClock: bodyClock, night: night)
                    agendaCard(bodyClock: bodyClock, night: night)
                    stabilityCard(bodyClock)
                    travelLink
                } else {
                    GatheringNights(
                        title: "Building your body clock",
                        message: "Zoon needs \(BodyClock.minimumNights) nights of history before it can estimate your preferred sleep window.",
                        nights: coordinator.recentNights.count,
                        needed: BodyClock.minimumNights
                    )
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Body Clock")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    showingMethod = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("How is this estimated?")
            }
        }
        .sheet(isPresented: $showingMethod) { methodSheet }
    }

    // MARK: - Travel

    /// Travel Sleep Guidance lives behind this screen rather than in the
    /// tab bar.
    ///
    /// The plan is expressed entirely in the numbers this screen draws --
    /// your onset, your wake, the morning window the Light card uses. Giving
    /// it its own tab would present it as a second opinion about the same
    /// body clock instead of that clock under travel conditions.
    private var travelLink: some View {
        NavigationLink {
            TravelPlanView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "airplane")
                    .font(Theme.text(14, weight: .semibold))
                    .foregroundStyle(Theme.Family.circadian)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crossing time zones")
                        .font(Theme.label(14, weight: .semibold))
                    Text("A schedule for shifting this clock, built around where it sits now.")
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(Theme.text(11, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Build a travel plan for crossing time zones")
    }

    // MARK: - Ring

    /// The orbit itself, plus the one sentence that says what it shows. The
    /// dial, its drag-to-inspect and its accessibility live in
    /// `ZoonBodyClockOrbit`; this only decides what goes on it.
    private func ring(bodyClock: BodyClock, night: SleepNightFeatures) -> some View {
        let driftMinutes = bodyClock.drift(of: night.bedtime) ?? 0
        let alignment = alignmentScore(driftMinutes: driftMinutes)
        let energyMarks = energyWindows(bodyClock: bodyClock, night: night)

        return VStack(spacing: 16) {
            ZoonBodyClockOrbit(
                bodyClock: bodyClock,
                night: night,
                energyMarks: energyMarks,
                alignment: alignment,
                agenda: agenda(bodyClock: bodyClock, night: night),
                inspectedFraction: $inspectedFraction
            )

            HStack(spacing: 14) {
                legend(color: Theme.Family.sleep.opacity(0.35), label: "Usual window")
                legend(color: Theme.Family.sleep, label: "Last night")
                legend(color: Theme.Family.circadian, label: "Energy")
            }

            Text(alignmentSentence(driftMinutes: driftMinutes))
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(Theme.text(10)).foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Alignment

    private func alignmentScore(driftMinutes: Double) -> Double {
        Statistics.interpolate(abs(driftMinutes), anchors: [
            (0, 100), (15, 100), (30, 90), (60, 75), (90, 55), (120, 35), (180, 10), (240, 0)
        ])
    }

    private func alignmentSentence(driftMinutes: Double) -> String {
        guard abs(driftMinutes) >= 10 else {
            return "Your sleep started right around your usual preferred timing."
        }
        let direction = driftMinutes > 0 ? "later" : "earlier"
        return "Your sleep started about \(Int(abs(driftMinutes))) minutes \(direction) than your recent preferred timing."
    }

    // MARK: - Stability

    private func stabilityCard(_ bodyClock: BodyClock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Rhythm Stability", systemImage: "waveform.path")
                Spacer()
                StatusPill(text: bodyClock.stability.label, tint: stabilityTint(bodyClock.stability))
            }
            Text(bodyClock.stability.detail)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
        }
        .glassCard()
    }

    private func stabilityTint(_ stability: BodyClock.Stability) -> Color {
        switch stability {
        case .tight: Theme.Metric.recoveryHigh
        case .typical: Theme.Metric.battery
        case .scattered: Theme.Metric.recoveryMid
        }
    }

    // MARK: - The day's named moments

    /// Peak, dip, and wind-down only. Morning rise and second wind sit close
    /// enough to the window edges already on the dial that marking them too
    /// would be noise around the same arc.
    private func energyWindows(bodyClock: BodyClock, night: SleepNightFeatures) -> [EnergyForecast.Window] {
        EnergyForecast.compute(
            wakeTime: night.wakeTime,
            sleepDebtMinutes: night.sleepDebtMinutes ?? 0,
            windDownHour: bodyClock.isEstimate ? nil : bodyClock.onsetHour
        ).windows.filter {
            $0.kind == .morningPeak || $0.kind == .afternoonDip || $0.kind == .windDown
        }
    }

    private func agenda(bodyClock: BodyClock, night: SleepNightFeatures) -> [BodyClockAgenda.Moment] {
        BodyClockAgenda.moments(
            bodyClock: bodyClock,
            energyMarks: energyWindows(bodyClock: bodyClock, night: night)
        )
    }

    /// The day as a list of named times.
    ///
    /// The dial alone could only ever say what the finger was on. Someone
    /// who does not already know a body clock has moments has no reason to
    /// go looking for them by dragging, so they are written out -- and
    /// tapping one moves the dial to it, which is how the two halves teach
    /// each other.
    private func agendaCard(bodyClock: BodyClock, night: SleepNightFeatures) -> some View {
        let moments = agenda(bodyClock: bodyClock, night: night)
        let selected = inspectedFraction.flatMap { BodyClockAgenda.moment(atFraction: $0, in: moments) }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your day", systemImage: "list.bullet")
            ForEach(moments) { moment in
                Button {
                    Haptics.select()
                    withAnimation(Motion.respecting(reduceMotion, Motion.scrub)) {
                        // Tapping the selected moment again clears it, so
                        // the dial can be returned to its resting state
                        // without hunting for empty space on the ring.
                        inspectedFraction = selected == moment ? nil : BodyClockAgenda.fraction(of: moment)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(BodyClock.formatted(hour: moment.hour))
                            .font(Theme.label(13, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 58, alignment: .leading)
                        Image(systemName: moment.symbol)
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.Family.circadian)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(moment.label)
                                .font(Theme.text(13, weight: .medium))
                            if selected == moment {
                                Text(moment.detail)
                                    .font(Theme.evidence)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        selected == moment ? Theme.neutral(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(BodyClock.formatted(hour: moment.hour)), \(moment.label)")
                .accessibilityHint(moment.detail)
                .accessibilityAddTraits(selected == moment ? [.isSelected] : [])
            }
        }
        .glassCard()
    }

    // MARK: - Method

    /// Behind an info button rather than a permanent card. The spec is
    /// explicit that the method must not clutter the primary visual -- and
    /// it is read once, while the dial is read every day.
    private var methodSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("""
                        This is an estimated body clock, not a direct measurement. Nothing worn on \
                        a wrist measures circadian phase.
                        """)
                        .font(Theme.text(14))
                    Text("""
                        It is built from your recent sleep midpoint, bedtime, wake time and \
                        regularity, averaged as clock positions rather than plain numbers so a \
                        night crossing midnight doesn't distort the result.
                        """)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("""
                        The energy peak, dip and wind-down are a forecast from your wake time and \
                        sleep debt, not a measurement of how alert you were. The light window is \
                        the \(Int(LightCoach.morningWindowMinutes)) minutes after waking, when \
                        outdoor light does the most to anchor tonight's timing.
                        """)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .nightBackground()
            .navigationTitle("How is this estimated?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingMethod = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Body Clock") {
    NavigationStack { BodyClockView() }
        .zoonPreviewEnvironment()
}
