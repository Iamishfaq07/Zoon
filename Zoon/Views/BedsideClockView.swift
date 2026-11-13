import SwiftUI
import UIKit

/// The phone as a bedside clock: the time, when you wake, and a moon that
/// fills as the night passes, on a black screen in a colour that keeps the
/// room dark.
///
/// Everything else in Zoon is read before bed or after waking. This is the
/// one screen meant to be glanced at in the middle of the night, so it obeys
/// different rules: no white anywhere, nothing that moves, type large enough
/// to read without glasses, and controls that fade away after a few seconds
/// so the only thing lit is the time.
///
/// In the twenty minutes before the wake the screen brightens from black to
/// warm light (`DawnRamp`): a sunrise, for a room that has none.
///
/// Presented full screen. The display stays awake while it is open and goes
/// back to normal the moment it closes.
struct BedsideClockView: View {

    /// The colour the whole screen is drawn in.
    enum Tone: String, CaseIterable, Identifiable {
        case red, amber, moon

        var id: String { rawValue }

        var label: String {
            switch self {
            case .red: "Red"
            case .amber: "Amber"
            case .moon: "Moon"
            }
        }

        /// Red is the default: it disturbs dark adaptation least, which is
        /// why it is the colour of every night-vision instrument.
        var color: Color {
            switch self {
            case .red: Color(red: 0.86, green: 0.16, blue: 0.12)
            case .amber: Color(red: 0.95, green: 0.58, blue: 0.16)
            case .moon: Color(red: 0.72, green: 0.70, blue: 0.92)
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(SoundscapeEngine.self) private var audio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("zoon.bedside.tone") private var toneRaw = Tone.red.rawValue
    @AppStorage("zoon.bedside.dim") private var dim = 0.25
    /// Brighten gradually before the wake. On unless switched off.
    @AppStorage("zoon.bedside.sunrise") private var sunrise = true

    @State private var opened = Date.now
    @State private var showsControls = true
    @State private var hideTask: Task<Void, Never>?

    private var tone: Tone { Tone(rawValue: toneRaw) ?? .red }

    /// The armed alarm if there is one ahead, else tonight's planned wake.
    /// Nothing when neither is within a night's reach: a wake time 20 hours
    /// off is not information anyone wants at 2am.
    private func wakeTime(at now: Date) -> Date? {
        // The resolved episode, as every Tonight surface uses: it honours a
        // saved schedule, and exists without a recorded night.
        //
        // The alarm time is read from the store on every tick, never held:
        // the app re-arms it on its own `WakeAlarm` whenever it comes
        // forward, and a copy taken here would not hear of it.
        let candidates = [WakeAlarm.storedScheduledWakeTime, coordinator.tonightEpisode(now: opened)?.wake]
        return candidates
            .compactMap { $0 }
            .first { $0 > now && $0.timeIntervalSince(now) < 16 * 3600 }
    }

    /// The wake the sunrise is timed to. Unlike `wakeTime(at:)` it keeps a
    /// wake that has just passed, so the light holds for a while after it
    /// and does not snap back to dark at the minute you are meant to get up.
    private func dawnWake(at now: Date) -> Date? {
        [WakeAlarm.storedScheduledWakeTime, coordinator.tonightEpisode(now: opened)?.wake]
            .compactMap { $0 }
            .first { $0.timeIntervalSince(now) > -30 * 60 && $0.timeIntervalSince(now) < 16 * 3600 }
    }

    /// Black through ember to warm morning light. Red rises first and blue
    /// last, as the sky does.
    private static func dawnColor(_ dawn: Double) -> Color {
        Color(red: pow(dawn, 0.6), green: 0.80 * pow(dawn, 1.4), blue: 0.52 * pow(dawn, 2.2))
    }

    /// What the clock is drawn in: the chosen tone at night, and a dark ink
    /// once the screen behind it is bright enough to need one.
    private func ink(_ dawn: Double) -> Color {
        dawn > 0.55 ? Color(red: 0.16, green: 0.07, blue: 0.03) : tone.color
    }

    var body: some View {
        // One tick a minute: the clock shows no seconds, and a bedside
        // screen should spend as little as it can.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let wake = wakeTime(at: now)
            let dawn = sunrise ? DawnRamp.progress(now: now, wake: dawnWake(at: now)) : 0
            ZStack {
                Color.black.ignoresSafeArea()
                // The sunrise: nothing until twenty minutes before the wake,
                // then the whole screen warms, a step each minute, eased so
                // the steps do not show.
                Self.dawnColor(dawn)
                    .ignoresSafeArea()
                    .animation(.linear(duration: 55), value: dawn)

                VStack(spacing: 18) {
                    moon(now: now, wake: wake, ink: ink(dawn))

                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(size: 96, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel("The time is \(now.formatted(date: .omitted, time: .shortened))")

                    if let wake {
                        VStack(spacing: 4) {
                            Label(
                                "Wake \(wake.formatted(date: .omitted, time: .shortened))",
                                systemImage: WakeAlarm.storedScheduledWakeTime == wake ? "alarm.fill" : "sunrise.fill"
                            )
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            Text("\(SleepNightFeatures.formatMinutes(wake.timeIntervalSince(now) / 60)) left")
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .opacity(0.7)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .foregroundStyle(ink(dawn))
                .padding(.horizontal, 24)
                // Moved a few points each minute so no pixel stays lit all
                // night.
                .offset(Self.drift(at: now))
                // Dimmed by fading towards black, not by the system
                // brightness, which would stay changed after the app closes.
                // The dimming lifts as the sunrise comes up.
                .opacity(1 - dim * 0.75 * (1 - dawn))

                if showsControls {
                    controls(ink: ink(dawn))
                        .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { revealControls() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            opened = .now
            UIApplication.shared.isIdleTimerDisabled = true
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Fills from the moment the clock was opened to the wake time, so a
    /// glance says how much of the night is behind you without any sums.
    private func moon(now: Date, wake: Date?, ink: Color) -> some View {
        let fraction: Double = {
            guard let wake, wake > opened else { return 0.5 }
            return min(1, max(0.04, now.timeIntervalSince(opened) / wake.timeIntervalSince(opened)))
        }()
        return MoonFill(fill: fraction, active: false, size: 120)
            // The moon's own colours would put white on the screen. Greyed,
            // then multiplied by the tone: lit parts take the tone's colour
            // and the dark side stays dark.
            .saturation(0)
            .colorMultiply(ink)
            .opacity(0.85)
            .accessibilityHidden(true)
    }

    private func controls(ink: Color) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(ink.opacity(0.16), in: Circle())
                }
                .accessibilityLabel("Close bedside clock")
            }
            Spacer()
            VStack(spacing: 16) {
                if audio.playing != nil {
                    Button {
                        if audio.isPlaying { audio.pauseForUser() } else { audio.resumeFromPause() }
                        scheduleHide()
                    } label: {
                        Label(
                            audio.isPlaying ? "Pause sounds" : "Resume sounds",
                            systemImage: audio.isPlaying ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(ink.opacity(0.16), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    ForEach(Tone.allCases) { option in
                        Button {
                            toneRaw = option.rawValue
                            scheduleHide()
                        } label: {
                            Text(option.label)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(option.color)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(option.color.opacity(option == tone ? 0.24 : 0.08), in: Capsule())
                        }
                        .accessibilityLabel("\(option.label) colour")
                        .accessibilityAddTraits(option == tone ? .isSelected : [])
                    }
                }

                Button {
                    sunrise.toggle()
                    scheduleHide()
                } label: {
                    Label(
                        sunrise ? "Sunrise wake on" : "Sunrise wake off",
                        systemImage: sunrise ? "sunrise.fill" : "sunrise"
                    )
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(ink.opacity(sunrise ? 0.24 : 0.08), in: Capsule())
                }
                .accessibilityHint("The screen brightens over \(Int(DawnRamp.leadMinutes)) minutes before your wake time")

                HStack(spacing: 12) {
                    Image(systemName: "sun.min")
                    Slider(value: Binding(
                        get: { 1 - dim },
                        set: { dim = 1 - $0; scheduleHide() }
                    ), in: 0...1)
                    .tint(ink)
                    .accessibilityLabel("Brightness")
                    Image(systemName: "sun.max")
                }
                .font(.system(size: 15))
            }
            .padding(.bottom, 12)
        }
        .foregroundStyle(ink)
        .buttonStyle(.plain)
        .padding(20)
    }

    private func revealControls() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsControls = true }
        scheduleHide()
    }

    /// Controls fade six seconds after the last touch, leaving the time.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.6)) { showsControls = false }
        }
    }

    /// A slow wander of up to a dozen points, repeating every 20 minutes.
    private static func drift(at date: Date) -> CGSize {
        let minute = Calendar.current.component(.minute, from: date)
        let angle = Double(minute % 20) / 20 * 2 * .pi
        return CGSize(width: cos(angle) * 12, height: sin(angle) * 12)
    }
}

#Preview("Bedside clock") {
    BedsideClockView()
        .zoonPreviewEnvironment()
}
