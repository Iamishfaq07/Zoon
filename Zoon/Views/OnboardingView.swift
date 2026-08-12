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
    @State private var moonGlow = false

    private let pageCount = 3

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.heroGlow.ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                TabView(selection: $page) {
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
    }

    // MARK: - Pages

    private var welcome: some View {
        page(
            art: moon,
            title: "Zoon",
            // The Kashmiri word is right-to-left, and a bare RTL run inside an
            // LTR sentence drags the neighbouring punctuation with it — this
            // line rendered as ".moon in Kashmiri — زوٗن" until the isolate was
            // added. U+2068 FIRST STRONG ISOLATE / U+2069 POP DIRECTIONAL
            // ISOLATE fence the run off so the bidi algorithm resolves the rest
            // of the line as LTR. Caught from a CI screenshot; it is invisible
            // in source, where the characters are stored in logical order.
            subtitle: "\u{2068}زوٗن\u{2069} — *moon* in Kashmiri",
            body: """
                Zoon reads the sleep your Apple Watch already records and explains \
                why last night went the way it did — not just how long it lasted.
                """
        )
    }

    private var privacy: some View {
        page(
            art: shield,
            title: "It stays on your phone",
            subtitle: "No account. No server. No network code.",
            body: """
                Zoon reads from Health and never writes to it. Everything — every \
                score, every insight, every sound — is computed on this device.

                Next, iOS will list what Zoon may read, each with its own switch. \
                Leave every switch on, especially Sleep — Zoon cannot function \
                without it, and cannot tell afterward if one got turned off.
                """
        )
    }

    private var goal: some View {
        page(
            art: goalDial,
            title: "How much sleep do you want?",
            subtitle: "Everything is measured against this, not an average.",
            body: """
                Sleep debt, sleep performance, tonight's bedtime — all of it is \
                relative to your target. Change it any time in Settings.
                """
        )
    }

    // MARK: - Art

    private var moon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Metric.sleep.opacity(0.55), .clear],
                        center: .center, startRadius: 8, endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
                .scaleEffect(moonGlow ? 1.06 : 0.94)

            Image(systemName: "moon.stars.fill")
                .font(Theme.text(88, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(white: 0.99), Theme.Metric.sleep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                moonGlow = true
            }
        }
    }

    private var shield: some View {
        Image(systemName: "lock.shield.fill")
            .font(Theme.text(78, weight: .light))
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.Metric.recoveryHigh, Theme.Metric.battery],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(height: 260)
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
                            startPoint: .topLeading, endPoint: .bottomTrailing
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

            // Quarter-hour steps: finer is false precision for a target, and
            // coarser can't express 7h30m, which is a very common answer.
            Slider(value: $goalHours, in: 5...11, step: 0.25)
                .tint(Theme.Metric.sleep)
                .padding(.horizontal, 40)
        }
        .frame(height: 260)
    }

    // MARK: - Chrome

    private func page(
        art: some View,
        title: String,
        subtitle: LocalizedStringKey,
        body: String
    ) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            art
            VStack(spacing: 8) {
                Text(title)
                    .font(Theme.numeral(31))
                Text(subtitle)
                    .font(Theme.label(14, weight: .medium))
                    .foregroundStyle(Theme.Metric.sleep)
                    .multilineTextAlignment(.center)
            }
            Text(body)
                .font(Theme.text(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
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
            .background(
                LinearGradient(
                    colors: [Theme.Metric.sleep, Theme.Metric.battery],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .foregroundStyle(.black)
        }
        .disabled(isRequestingHealth)
    }

    private var buttonTitle: String {
        switch page {
        case 0: "Get started"
        case 1: "Connect Health"
        default: "Start"
        }
    }

    private func advance() {
        switch page {
        case 0:
            withAnimation { page = 1 }

        case 1:
            // The system sheet is the next thing on screen, which is the whole
            // point of the page before it.
            isRequestingHealth = true
            Task {
                await coordinator.requestHealthAccess()
                isRequestingHealth = false
                withAnimation { page = 2 }
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
