import SwiftUI
#if os(watchOS)
// For `WKInterfaceDevice`, the only haptic API the watch has. Guarded
// because this file compiles into every target, and WatchKit exists on
// none of the others.
import WatchKit
#endif

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
    /// 0.22 s: inside the 180-250 ms the release brief sets for selection
    /// feedback (it was 0.26).
    static let tap = Animation.snappy(duration: 0.22)

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
    /// 0.6 s: inside the brief's 450-650 ms for a single orienting reveal
    /// (it was 0.7).
    static let draw = Animation.easeOut(duration: 0.6)

    /// Scrub/selection updates: the highlighted mark and the headline value
    /// move together. Short enough that a finger dragging never outruns it.
    static let scrub = Animation.snappy(duration: 0.12)

    /// The launch splash: the moon settling into place before the app
    /// appears behind it. Slower and softer than `hero` — this plays once
    /// per cold launch and is the only animation in the app nobody chose to
    /// trigger, so it has to feel like the app waking up rather than like a
    /// delay someone inserted.
    static let splash = Animation.spring(response: 0.9, dampingFraction: 0.8)

    /// How long the splash holds before handing over. Short on purpose: a
    /// branded first frame is worth a beat, and nothing more.
    static let splashHold: Double = 0.4

    /// A screen swapping one whole state for another — loading → loaded,
    /// empty → content. Without this the swap is a hard cut, which on the
    /// morning screen means the loading moon vanishes mid-sweep and last
    /// night appears fully formed in the same frame.
    ///
    /// Asymmetric on purpose: the arriving state lifts and scales in the
    /// same way `EntranceModifier` does, so a state change and a first
    /// appearance read as the same gesture, while the leaving state only
    /// fades — a state on its way out that also moves reads as two things
    /// happening instead of one.
    static func stateChange(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity
        )
    }

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

/// Crossfades a view when its state identity changes. See
/// `Motion.stateChange(reduceMotion:)`.
///
/// `id` is what makes this work: SwiftUI only runs a transition when a view
/// is inserted or removed, and a `switch` returning a different branch of
/// the same `@ViewBuilder` is, as far as the view graph is concerned, the
/// same view with new contents. Keying identity to the state forces the real
/// insert/remove pair the transition needs.
struct StateTransitionModifier: ViewModifier {
    let value: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .id(value)
            .transition(Motion.stateChange(reduceMotion: reduceMotion))
            .animation(Motion.respecting(reduceMotion, Motion.navigation), value: value)
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

    /// Crossfade between mutually exclusive states of one screen. Pass
    /// something that changes when the state does — a case name, an enum
    /// that is `Hashable`, a count. See `StateTransitionModifier`.
    func stateTransition(_ value: some Hashable) -> some View {
        modifier(StateTransitionModifier(value: AnyHashable(value)))
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .shadow(color: tint.opacity(active && phase ? 0.55 : 0.18), radius: phase ? 16 : 8)
            .onChange(of: active) { _, isActive in
                isActive ? start() : stop()
            }
            .onAppear { start() }
            // A `repeatForever` animation does not stop on its own. Without
            // these two it keeps cycling behind a backgrounded app and behind
            // whatever the person navigated to next -- for a pacer attached
            // to a nap or a sleep session, that is potentially all night.
            // The V10 spec asks for exactly this: pause when the screen is
            // off, when the app is backgrounded, and when the view is
            // offscreen.
            .onDisappear { stop() }
            .onChange(of: scenePhase) { _, newPhase in
                newPhase == .active ? start() : stop()
            }
    }

    private func start() {
        guard active, !reduceMotion, scenePhase == .active else { return }
        // ~4 seconds per cycle, which is close to a slow resting breath. The
        // rate is the point: it is the pace you want someone to settle to.
        withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
            phase = true
        }
    }

    /// Cuts the repeating animation rather than animating back to rest.
    ///
    /// Assigning `phase = false` inside the still-running `repeatForever`
    /// leaves the animation attached to the property, so the glow keeps
    /// cycling toward a target that has moved. Disabling animations for this
    /// one transaction detaches it, which is what stopping means here.
    private func stop() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { phase = false }
    }
}

/// Haptics, wrapped so call sites don't each construct a generator.
///
/// iOS-only: the widget extension compiles this file too, and UIKit's feedback
/// generators aren't available there.
///
/// `@MainActor` because the UIKit generators are; every caller is a view or a
/// main-actor controller.
@MainActor
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
    #elseif os(watchOS)
    // The watch had no `Haptics` at all: every call site played
    // `WKInterfaceDevice.current().play(.click)` directly, so a confirmed
    // alarm, a rejected input and a scrub detent all felt identical, and the
    // vocabulary the phone teaches did not survive onto the wrist.
    //
    // `WKHapticType` is a fixed set of system patterns rather than an
    // intensity an app chooses, so these are mappings onto the closest
    // system meaning, not reproductions of the phone's feel.
    static func tap() {
        WKInterfaceDevice.current().play(.click)
    }

    static func select() {
        WKInterfaceDevice.current().play(.click)
    }

    static func success() {
        WKInterfaceDevice.current().play(.success)
    }

    /// `.notification`, not `.failure`. A warning here means something wants
    /// attention, not that an action was rejected -- `.failure` is the
    /// stronger, more final pattern and would overstate it.
    static func warning() {
        WKInterfaceDevice.current().play(.notification)
    }

    /// The same pattern the crown itself uses for a detent, which is what
    /// scrubbing on the watch is usually driven by.
    static func scrubDetent() {
        WKInterfaceDevice.current().play(.click)
    }

    /// `.start` marks a transition being reached rather than an outcome
    /// being delivered, which is what a milestone is. `.success` is reserved
    /// for something the person actually completed.
    static func milestone() {
        WKInterfaceDevice.current().play(.start)
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
