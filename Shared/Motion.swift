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

    // MARK: - Named tiers
    //
    // The redesign spec asks for a centralized "ZoonMotion" with four named
    // tiers: micro, standard, hero, navigation. Two of those are exactly
    // `tap` and `value` above under a different name -- rather than
    // duplicate or rename them (renaming would touch every existing call
    // site for no behavioural change), `micro` and `standard` are aliases.
    // `hero` and `heroTransition` are genuinely new: nothing in the app
    // before this needed a slower, more expressive curve for a big single
    // reveal (a score settling into place, an orb morphing between states)
    // or a push/pop-style navigation feel distinct from either.

    /// Smallest interactions: toggles, checkbox flourishes, a value ticking
    /// up by one. Alias for `tap` -- same feel, named for where the spec's
    /// tier list expects it.
    static let micro = tap

    /// Everyday content transitions: cards settling, values updating,
    /// picker selections. Alias for `value`.
    static let standard = value

    /// A single, large, attention-owning reveal -- a hero score settling
    /// into place, an orb morphing between summary and detail. Slower and
    /// more expressive than `entrance`: this fires once, not stacked eight
    /// times down a scroll view, so it can afford to take a beat longer.
    static let hero = Animation.spring(response: 0.75, dampingFraction: 0.82)

    /// Push/pop-style navigation and matched-geometry transitions between
    /// screens -- deliberately quicker and less springy than `hero`, since
    /// a screen transition that overshoots reads as sluggish rather than
    /// alive.
    static let navigation = Animation.smooth(duration: 0.4)

    // MARK: - V8 additions

    /// A chart or ribbon revealing left → right the first time it appears.
    /// Fires once per data change, never on scroll re-entry (callers gate
    /// on `.onAppear` + a `@State` flag, not on visibility).
    static let draw = Animation.easeOut(duration: 0.7)

    /// Scrub/selection updates: the highlighted mark and the headline value
    /// move together. Short enough that a finger dragging never outruns it.
    static let scrub = Animation.snappy(duration: 0.12)

    /// The Today entrance sequence, expressed as delays from first frame.
    /// Total perceived duration is under half a second -- the screen is
    /// opened half-asleep every morning and must not make anyone wait.
    enum Entry {
        static let background: Double = 0
        static let hero: Double = 0.05
        static let heroValue: Double = 0.18
        static let supporting: Double = 0.28
        static let secondary: Double = 0.36
    }

    /// The right animation for a state change given the Reduce Motion
    /// setting: `nil` (instant) when it's on, the supplied curve otherwise.
    /// Every V8 view routes its `withAnimation` through this so the
    /// accessibility check can't be forgotten at a call site.
    static func respecting(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// The per-view "has this already animated in?" flag `Motion.draw` relies
/// on, so a chart draws once when its data arrives and never again as the
/// user scrolls it on and off screen.
struct DrawOnce: ViewModifier {
    /// The data identity; a change here re-arms the draw.
    let id: AnyHashable
    @Binding var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { run() }
            .onChange(of: id) { _, _ in
                progress = 0
                run()
            }
    }

    private func run() {
        guard !reduceMotion else {
            progress = 1
            return
        }
        withAnimation(Motion.draw) { progress = 1 }
    }
}

extension View {
    /// Drives `progress` 0 → 1 once on appear and again only when `id`
    /// changes. See `DrawOnce`.
    func drawOnce(id: some Hashable, progress: Binding<Double>) -> some View {
        modifier(DrawOnce(id: AnyHashable(id), progress: progress))
    }
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

    /// One detent while scrubbing a chart or ring: fires only when the
    /// selection actually changes to a new element, never per pixel.
    /// `.soft` rather than `.light` -- a scrub crosses several detents in a
    /// second, and a light impact repeated that fast reads as buzzing.
    static func scrubDetent() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    /// A moment on a timeline being reached, or a milestone completing.
    static func milestone() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    #else
    static func tap() {}
    static func select() {}
    static func success() {}
    static func warning() {}
    static func scrubDetent() {}
    static func milestone() {}
    #endif
}
