import SwiftUI

/// First run.
///
/// Three jobs, in this order:
///
/// 1. **Say what the app is** before asking for anything.
/// 2. **Ask for Health access with context.** The system sheet gives no reason;
///    a screen that explains what is read and why, immediately before it,
///    roughly doubles the odds of a grant — and a denial here is invisible to
///    the app forever after, so there is no second chance to explain.
/// 3. **Get the sleep goal**, the one number every comparison in the app is
///    measured against.
///
/// Deliberately short. A wellness app that opens with eight screens of
/// onboarding has already spent the goodwill it needed for the permission
/// prompt.
struct OnboardingView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var goalHours: Double = 8
    @State private var isRequestingHealth = false
    @State private var hasRequestedHealth = false

    private let pageCount = 3

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            NightSky()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: pageSelection) {
                    welcome.tag(0)
                    privacy.tag(1)
                    goal.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy(duration: 0.35), value: page)

                dots
                    .padding(.bottom, 18)

                actionButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 26)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            goalHours = preferences.sleepGoalMinutes / 60
        }
    }

    // MARK: - The Health gate

    /// A swipe must not carry anyone past the Health page before the system
    /// sheet has been shown.
    ///
    /// `TabView(.page)` pages on a drag as well as on the button, so a flick
    /// from the welcome page landed on the goal page, "Open Zoon" completed
    /// onboarding, and the app ran having never asked for anything. Every
    /// query then returned nothing, with no way back: the sheet is offered
    /// once, so the only remedy left was finding Zoon in Settings by hand.
    ///
    /// The gate is "has been asked", not "has granted", because granted is not
    /// knowable. HealthKit deliberately never reports *read* authorization --
    /// `authorizationStatus(for:)` answers for writes only -- so an app cannot
    /// tell a denial from an empty Health store. Asking is the part that was
    /// being skipped, and it is the part this can guarantee.
    private var pageSelection: Binding<Int> {
        Binding(
            get: { page },
            set: { page = min($0, furthestAllowedPage) }
        )
    }

    private var furthestAllowedPage: Int {
        guard needsHealthGate else { return pageCount - 1 }
        return hasRequestedHealth ? pageCount - 1 : 1
    }

    /// No gate where there is nothing to ask for: an iPad without Health, or a
    /// demo/screenshot launch, where `requestHealthAccess()` returns straight
    /// away and blocking would strand the run on page 1 forever.
    private var needsHealthGate: Bool {
        DataEnvironment.current.isLive && HealthKitManager.isHealthDataAvailable
    }

    // MARK: - Pages

    private var welcome: some View {
        page(
            art: InteractiveMoon(size: 236),
            kicker: "\u{2068}زوٗن\u{2069}",
            title: "The night, in one look",
            subtitle: "\u{2068}راتھ\u{2069}  ·  Move the moon. This is not another tracker.",
            body: """
                Zoon reads the sleep your Watch already kept and tells the story \
                of last night — why it went the way it did, not just how long it lasted.
                """
        )
    }

    private var privacy: some View {
        page(
            art: privacyMark,
            kicker: "On this phone",
            title: "It never leaves",
            subtitle: "No account. No server. No network code.",
            body: """
                Zoon reads from Health and never writes to it. Everything is computed here.

                Next, iOS will ask twice: first for Sleep, which Zoon cannot \
                function without, then for heart rate, HRV, breathing and the rest, \
                which sharpen Recovery and Body Signals. Leave everything on if you can \
                — Zoon cannot tell afterward if a switch got turned off.
                """
        )
    }

    private var goal: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            goalDial
            VStack(spacing: 8) {
                Text("\u{2068}نِندر\u{2069}")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                    .tracking(3)
                Text("How long do you want to sleep?")
                    .font(Theme.numeral(31))
                    .multilineTextAlignment(.center)
                Text("Every comparison uses this number, not a crowd average.")
                    .font(Theme.label(14, weight: .medium))
                    .foregroundStyle(Theme.Metric.sleep)
                    .multilineTextAlignment(.center)
            }
            profilePickers
            Spacer(minLength: 8)
        }
    }

    /// Age / sex / BMI belong here rather than a fourth lecture: they now
    /// change the deep-sleep prior, and burying them in Settings means most
    /// people never set them. All three stay optional.
    private var profilePickers: some View {
        VStack(spacing: 10) {
            Text("Optional — used only to pick a demographic deep-sleep prior, so a typical older night is not marked down against a young-adult target.")
                .font(Theme.text(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            HStack(spacing: 10) {
                Picker(
                    "Age",
                    selection: Binding(
                        get: { preferences.age ?? 0 },
                        set: { preferences.age = $0 > 0 ? $0 : nil }
                    )
                ) {
                    Text("Age").tag(0)
                    ForEach(16...90, id: \.self) { age in
                        Text("\(age)").tag(age)
                    }
                }
                .pickerStyle(.menu)

                Picker(
                    "Sex",
                    selection: Binding(
                        get: { preferences.biologicalSex },
                        set: { preferences.biologicalSex = $0 }
                    )
                ) {
                    Text("Sex").tag(DemographicBaseline.Sex.unspecified)
                    Text("Female").tag(DemographicBaseline.Sex.female)
                    Text("Male").tag(DemographicBaseline.Sex.male)
                }
                .pickerStyle(.menu)

                Picker(
                    "BMI",
                    selection: Binding(
                        get: { preferences.bodyMassIndex.map { Int($0.rounded()) } ?? 0 },
                        set: { preferences.bodyMassIndex = $0 > 0 ? Double($0) : nil }
                    )
                ) {
                    Text("BMI").tag(0)
                    ForEach(16...45, id: \.self) { bmi in
                        Text("\(bmi)").tag(bmi)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Art

    private var privacyMark: some View {
        ZStack {
            Circle()
                .stroke(Theme.neutral(0.14), lineWidth: 1)
                .frame(width: 168, height: 168)
            Circle()
                .stroke(Theme.neutral(0.22), lineWidth: 1)
                .frame(width: 124, height: 124)
            Image(systemName: "lock.shield.fill")
                .font(Theme.text(46, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(white: 0.96), Theme.Metric.sleep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(height: 236)
        .accessibilityHidden(true)
    }

    private var goalDial: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.neutral(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: (goalHours - 4) / 8)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.Metric.sleep, Theme.Metric.battery],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: goalHours)

                VStack(spacing: -2) {
                    Text(SleepNightFeatures.formatMinutes(goalHours * 60))
                        .font(Theme.numeral(30))
                        .monospacedDigit()
                    Text("a night")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)

            Slider(value: $goalHours, in: 5...11, step: 0.25)
                .tint(Theme.Metric.sleep)
                .padding(.horizontal, 40)
        }
        .frame(height: 236)
    }

    // MARK: - Chrome

    private func page(
        art: some View,
        kicker: String,
        title: String,
        subtitle: LocalizedStringKey,
        body: String
    ) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            art
            VStack(spacing: 8) {
                Text(kicker)
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                    .textCase(.uppercase)
                    .tracking(1.6)
                Text(title)
                    .font(Theme.numeral(31))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(Theme.label(14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(body)
                .font(Theme.text(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 28)
            Spacer(minLength: 8)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.Metric.sleep : Theme.neutral(0.20))
                    .frame(width: index == page ? 20 : 7, height: 7)
                    .animation(.snappy(duration: 0.3), value: page)
            }
        }
        .accessibilityHidden(true)
    }

    private var actionButton: some View {
        Button {
            advance()
        } label: {
            HStack(spacing: 8) {
                if isRequestingHealth {
                    ProgressView().tint(.black)
                }
                Text(buttonTitle)
                    .font(Theme.label(16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .foregroundStyle(.black)
        }
        .disabled(isRequestingHealth)
        .scaleEffect(isRequestingHealth ? 0.98 : 1)
    }

    private var buttonTitle: String {
        switch page {
        case 0: "Begin"
        case 1: "Connect Health"
        default: "Open Zoon"
        }
    }

    private func advance() {
        switch page {
        case 0:
            withAnimation(Motion.respecting(reduceMotion, Motion.navigation)) { page = 1 }

        case 1:
            isRequestingHealth = true
            Task {
                await coordinator.requestHealthAccess()
                isRequestingHealth = false
                // Set before the page changes: the gate reads this, so
                // advancing first would be clamped straight back to 1.
                hasRequestedHealth = true
                withAnimation(Motion.respecting(reduceMotion, Motion.navigation)) { page = 2 }
            }

        default:
            preferences.sleepGoalMinutes = goalHours * 60
            preferences.hasCompletedOnboarding = true
            Task { await coordinator.refresh() }
        }
    }
}

#Preview("Onboarding") {
    OnboardingView().zoonPreviewEnvironment()
}
