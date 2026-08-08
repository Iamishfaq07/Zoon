import SwiftUI

/// Zoon's motion vocabulary.
///
/// Collected in one place for the same reason the colours are: an app where
/// every screen invents its own timing feels assembled rather than designed,
/// and the differences are the kind nobody can name but everybody notices.
///
/// ## Reduce Motion is honoured everywhere
///
/// Every helper here degrades to an instant, non-animated result when the
/// accessibility setting is on. That matters more than usual in this app —
/// vestibular sensitivity and poor sleep travel together often enough that a
/// sleep app dismissing the setting would be a poor joke.
enum Motion {

    /// Cards settling in. Slightly springy, but critically damped enough not
    /// to overshoot twice — a dashboard that bounces reads as a toy.
    static let entrance = Animation.spring(response: 0.55, dampingFraction: 0.86)

    /// Value changes on an existing element: a ring filling, a bar re-scaling.
    static let value = Animation.smooth(duration: 0.65)

    /// Taps, toggles, selection. Fast enough to feel like a direct response.
    static let tap = Animation.snappy(duration: 0.26)

    /// How long each successive card waits before appearing.
    ///
    /// 45ms: enough to read as a cascade, short enough that the last card in a
    /// six-card screen is on screen within a third of a second. Longer feels
    /// like the app is showing off, and on a screen you open half-asleep every
    /// morning that wears out fast.
    static let stagger: Double = 0.045

    /// Cap on the cascade. Beyond this, later cards all share the last delay
    /// rather than accumulating — otherwise a long scroll view spends over a
    /// second animating content the user has already scrolled past.
    static let maxStaggerSteps = 8
}

/// Fades and lifts a view into place on first appearance.
///
/// `index` places it in the cascade. Applied to cards in a `VStack`, it reads
/// as the screen assembling top-down.
struct EntranceModifier: ViewModifier {

    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            // Scale is subtle on purpose. At 0.98 it reads as depth; at the
            // 0.9 that tutorials like, it reads as a popup.
            .scaleEffect(shown ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(
                    Motion.entrance.delay(
                        Double(min(index, Motion.maxStaggerSteps)) * Motion.stagger
                    )
                ) {
                    shown = true
                }
            }
    }
}

/// Presses in slightly while held. Applied to card-shaped buttons so a tap on
/// a large target still gives the feedback a small one does for free.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

extension View {

    /// Cascading entrance. See `EntranceModifier`.
    func entrance(_ index: Int = 0) -> some View {
        modifier(EntranceModifier(index: index))
    }

    /// A soft pulsing glow, for something that is genuinely live — a running
    /// nap timer, playing audio. Deliberately not decorative: a glow that
    /// pulses on static content teaches people to ignore it, and then the one
    /// that matters gets ignored too.
    func breathing(_ active: Bool, tint: Color) -> some View {
        modifier(BreathingModifier(active: active, tint: tint))
    }
}

struct BreathingModifier: ViewModifier {
    let active: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .shadow(color: tint.opacity(active && phase ? 0.55 : 0.18), radius: phase ? 16 : 8)
            .onChange(of: active) { _, isActive in
                guard isActive, !reduceMotion else {
                    phase = false
                    return
                }
                start()
            }
            .onAppear {
                guard active, !reduceMotion else { return }
                start()
            }
    }

    private func start() {
        // ~4 seconds per cycle, which is close to a slow resting breath. The
        // rate is the point: it is the pace you want someone to settle to.
        withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
            phase = true
        }
    }
}

/// Haptics, wrapped so call sites don't each construct a generator.
///
/// iOS-only: the widget extension compiles this file too, and UIKit's feedback
/// generators aren't available there.
enum Haptics {
    #if canImport(UIKit) && !os(watchOS)
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    #else
    static func tap() {}
    static func select() {}
    static func success() {}
    static func warning() {}
    #endif
}
