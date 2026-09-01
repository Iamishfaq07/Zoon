import SwiftUI
// For UIColor(dynamicProvider:) -- available on iOS and watchOS alike (this
// file compiles into both), which is what lets `adaptive(dark:light:)` below
// resolve per-trait without any call site needing `@Environment(\.colorScheme)`.
import UIKit

/// Zoon's visual language.
///
/// Dark-first by intention, not fashion: this is an app you open at 7am in a
/// dark bedroom and glance at on a lock screen at night, and Dark stays the
/// default (`UserPreferences.appearance`) for exactly that reason. Light and
/// System are real options, not a checkbox that quietly breaks the app --
/// the core surface tokens below (`background`, `heroGlow`, `cardStroke`,
/// `cardFill`) resolve per-trait via `adaptive(dark:light:)`, a soft-dawn
/// reinterpretation rather than a straight invert, which would fight the
/// saturated metric hues below.
///
/// Colours are declared as explicit sRGB rather than system semantic colours
/// because the metric hues carry meaning (a red recovery must read as *red*,
/// consistently, in both appearances and in a screenshot). Text and chrome still
/// use system materials so Dynamic Type, contrast settings, and vibrancy come
/// for free.
enum Theme {

    // MARK: - Surfaces

    /// Deep night gradient — the app's ground in Dark. "Zoon" means moon; the
    /// palette is the sky around it. In Light this becomes a soft dawn sky
    /// rather than a straight invert to white: an invert would fight the
    /// saturated metric hues, which were tuned to sit on something dark.
    ///
    /// `Color(uiColor:)` wrapping a `UIColor(dynamicProvider:)` rather than
    /// two separate `LinearGradient` constants picked by `\.colorScheme`
    /// at each call site, so every one of the dozens of places that already
    /// write `Theme.background` keeps working unchanged and adapts for free.
    static var background: LinearGradient {
        LinearGradient(
            colors: [
                // Light's top stop is warm pearl, not another cool tone --
                // previously all three light stops were blue/lavender-leaning
                // (B channel highest throughout), which reads as "faded Dark
                // Mode" rather than its own identity. A warm anchor at the
                // top settling into the existing cool silver/lavender/blue
                // stops below is the "Lunar Dawn" progression: warm pearl →
                // cool silver → lavender-grey → soft blue.
                // V8 "Lunar Night": the bottom stop used to lean violet
                // (B channel 0.200 against R 0.078), which made purple the
                // room rather than the accent. Graphite → midnight navy →
                // deep blue-black keeps the depth without the tint, so the
                // sleep-indigo hue reads as *the sleep colour* again instead
                // of "the colour of everything."
                //
                // Light is "Lunar Dawn": warm pearl into cool white into
                // very pale blue-grey. No lavender, so cards stop looking like
                // Dark Mode inverted.
                adaptive(dark: (0.024, 0.031, 0.070), light: (0.980, 0.973, 0.961)),
                adaptive(dark: (0.043, 0.055, 0.118), light: (0.957, 0.961, 0.973)),
                adaptive(dark: (0.055, 0.070, 0.160), light: (0.929, 0.937, 0.957))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Morning ground: midnight fading toward a subtle dawn, per the
    /// redesign spec's Dynamic Background System. Used by
    /// `ZoonAmbientBackground` rather than replacing `background` outright --
    /// swapping the ground under every existing screen without any visual
    /// verification capability in this environment would be a real
    /// regression risk, so this is opt-in infrastructure for screens (the
    /// Today hero in particular) that adopt it deliberately.
    static var morningBackground: LinearGradient {
        LinearGradient(
            colors: [
                adaptive(dark: (0.086, 0.078, 0.161), light: (0.996, 0.925, 0.878)),
                adaptive(dark: (0.067, 0.071, 0.157), light: (0.976, 0.929, 0.902)),
                adaptive(dark: (0.051, 0.063, 0.141), light: (0.949, 0.925, 0.976))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Day ground: cool blue-violet depth, still dark-first per the app's
    /// OLED-friendly default -- this isn't a light "daytime" background, it's
    /// the calmer, less nocturnal end of the same dark palette.
    static var dayBackground: LinearGradient {
        LinearGradient(
            colors: [
                adaptive(dark: (0.043, 0.063, 0.129), light: (0.918, 0.929, 0.976)),
                adaptive(dark: (0.055, 0.071, 0.161), light: (0.929, 0.925, 0.976)),
                adaptive(dark: (0.063, 0.055, 0.161), light: (0.945, 0.925, 0.973))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Evening ground: deeper indigo, the wind-down half of the day.
    static var eveningBackground: LinearGradient {
        LinearGradient(
            colors: [
                adaptive(dark: (0.035, 0.039, 0.098), light: (0.882, 0.867, 0.945)),
                adaptive(dark: (0.055, 0.051, 0.145), light: (0.906, 0.878, 0.949)),
                adaptive(dark: (0.086, 0.055, 0.184), light: (0.925, 0.878, 0.945))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Subtle top-glow used behind hero content.
    static var heroGlow: RadialGradient {
        RadialGradient(
            // Moon-blue rather than violet, and a notch quieter: the glow
            // is the moonlight on the sky, not a second purple layer.
            colors: [adaptive(dark: (0.30, 0.40, 0.92), light: (0.45, 0.55, 0.92)).opacity(0.26), .clear],
            center: .top,
            startRadius: 10,
            endRadius: 420
        )
    }

    /// Builds a `Color` that resolves to one sRGB triple in Dark and another
    /// in Light, following whatever the trait environment actually is
    /// (System, or an explicit override from `UserPreferences.appearance`
    /// applied via `.preferredColorScheme` further up the view tree) rather
    /// than a preference read here, which a `Color` has no way to do.
    ///
    /// iOS/widget only: `UIColor(dynamicProvider:)` and `.userInterfaceStyle`
    /// are unavailable on watchOS (confirmed by CI, not assumed -- the watch
    /// build failed on this the first time). watchOS falls back to `dark`
    /// unconditionally, which is a no-op change from before this file had
    /// any adaptive colors at all: the watch app has always been dark-only
    /// by deliberate design (see `watchBackground`'s doc comment on OLED
    /// battery cost), so Light on the watch was never on offer to begin with.
    private static func adaptive(
        dark: (Double, Double, Double),
        light: (Double, Double, Double)
    ) -> Color {
        #if os(watchOS)
        let (r, g, b) = dark
        return Color(red: r, green: g, blue: b)
        #else
        return Color(uiColor: UIColor { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #endif
    }

    /// Watch variant of the ground.
    ///
    /// Flatter and darker than the phone's. A watch OLED renders true black as
    /// pixels that are off, so a gradient that looks rich on a phone reads as
    /// grey haze on a wrist and costs battery to display. The tint is kept only
    /// at the top, where the app's identity needs to show.
    static let watchBackground = LinearGradient(
        colors: [
            Color(red: 0.055, green: 0.055, blue: 0.145),
            Color.black
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// A hairline edge. Needs a dark edge to read as glass once the surface
    /// behind it is pale rather than black, and needs *more* contrast than
    /// Dark to read at all: the ground is a pale lavender, not near-black,
    /// so the same low opacity that separates a card from Dark's ground all
    /// but vanishes against Light's.
    static var cardStroke: Color { cardTint(dark: (1, 1, 1, 0.08), light: (0, 0, 0, 0.16)) }

    /// The tint that sits between the blurred material and the stroke.
    ///
    /// Dark and Light are solving different problems here, not the same
    /// problem at different strengths -- that's why they're opposite
    /// *hues*, not just opposite alphas. In Dark, `.ultraThinMaterial`
    /// already reads as glass against the near-black ground; a faint white
    /// tint only needs to lift it slightly. In Light, a dark tint over the
    /// material would just desaturate the blur toward grey -- it was tried
    /// first and still looked cheap, because darkening translucency doesn't
    /// make it solid. What actually reads as a real card (compare this
    /// file's Settings screen, which uses opaque system-background rows and
    /// looks crisp for free) is pushing the material toward *opaque white*,
    /// which is a light tint at high alpha, not a dark one at low alpha.
    static var cardFill: Color { cardTint(dark: (1, 1, 1, 0.05), light: (1, 1, 1, 0.65)) }

    /// Builds a colour whose RGB *and* alpha both depend on the trait
    /// environment, via the same `UIColor(dynamicProvider:)` mechanism
    /// `adaptive(dark:light:)` uses for RGB alone -- needed here because
    /// `Color.opacity` takes a plain `Double` fixed at call time, so it
    /// can't itself vary per trait; only the colour it's applied to can.
    private static func cardTint(
        dark: (Double, Double, Double, Double),
        light: (Double, Double, Double, Double)
    ) -> Color {
        #if os(watchOS)
        let (r, g, b, a) = dark
        return Color(red: r, green: g, blue: b, opacity: a)
        #else
        return Color(uiColor: UIColor { traits in
            let (r, g, b, a) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: r, green: g, blue: b, alpha: a)
        })
        #endif
    }

    /// A card's drop shadow. Black at a fixed low opacity works in both
    /// appearances without branching: it's imperceptible against Dark's
    /// near-black ground (which needs none -- `.ultraThinMaterial` already
    /// separates from black on its own), and it's what gives a card real
    /// depth against Light's pale ground, where material + a hairline stroke
    /// alone reads as a flat pasted rectangle rather than glass.
    static let cardShadow = Color.black.opacity(0.14)

    /// A neutral overlay with caller-controlled strength. This is for rings,
    /// ticks and empty chart cells where a literal white works in Dark but
    /// disappears on the dawn palette in Light.
    ///
    /// Light doubles the caller's opacity, not just flips the hue: these
    /// tracks and ticks sit directly on a surface (a card's now-opaque fill,
    /// or the page background) rather than behind blurred material, so
    /// unlike `cardFill` this doesn't need a hue change to read -- black-on-
    /// light is already the right direction. But the same absolute opacity
    /// that separates from Dark's near-black ground is still too faint
    /// against Light's pale ground, the same gap `cardStroke` had before it
    /// was split per-appearance. `MetricRing`'s track (the ring around
    /// "Load today" on the Today screen) is the one call site verified by
    /// screenshot; the doubling is applied uniformly to the other ~15
    /// call sites (progress tracks, unselected pills, empty ring segments)
    /// by the same reasoning, not independently re-verified per screen.
    static func neutral(_ opacity: Double) -> Color {
        #if os(watchOS)
        return Color.white.opacity(opacity)
        #else
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: opacity)
                : UIColor(white: 0, alpha: min(opacity * 2, 1))
        })
        #endif
    }

    /// The live "now" marker on a dial -- Body Clock's orbit dot, on both
    /// the card and the full screen.
    ///
    /// Dark resolves to pure white, which is byte-identical to the hardcoded
    /// `Color.white` this replaced: the appearance the screenshots were taken
    /// against cannot change. Only the Light path is new, and it has to be,
    /// because a white dot with a white halo on a pale dial is the one marker
    /// in the app that could disappear into its own background.
    ///
    /// Not `neutral()`, despite that being the usual adaptive answer. neutral
    /// is a *translucent* ink for ticks and tracks, and this marker is opaque
    /// on purpose -- it is the one element on the dial that has to read as a
    /// solid object rather than as a graduation. The Light value is the app's
    /// own near-black navy rather than pure black, so the dot stays in the
    /// family the rest of the palette is drawn from.
    static var dialMarker: Color {
        adaptive(dark: (1, 1, 1), light: (0.09, 0.09, 0.16))
    }

    /// A glass card's specular highlight -- the soft sheen a curved glass
    /// surface catches along its top edge. Deliberately **not** built from
    /// `neutral`, which flips to black in Light on purpose (it needs to
    /// separate a chart tick from a pale background). A light reflection is
    /// a light reflection regardless of appearance -- inverting it to a dark
    /// smudge in Light would read as a stain, not glass.
    static func glassHighlight(_ opacity: Double) -> Color {
        Color.white.opacity(opacity)
    }

    // MARK: - Metric hues

    /// Derives a Light-appearance variant of a hue tuned for Dark.
    ///
    /// These hues were picked to pop against Dark's near-black ground, and
    /// every one of them was, until this, a flat `Color(red:green:blue:)`
    /// with no Light counterpart at all -- unlike every surface token above
    /// (`cardFill`, `cardStroke`, `neutral`), which already went through a
    /// Dark/Light split. The gap this closes: a hue tuned to pop against
    /// near-black reads as neon/candy-colored transplanted unmodified onto
    /// Light's pale pastel ground, which is what a real-device report
    /// described as the Light theme "still feeling cheap" after cardFill/
    /// cardStroke/materials had already each had their own pass (see their
    /// doc comments above) -- the surfaces were never the actual gap.
    ///
    /// Darkened ~18% for the contrast a pale background needs, then pulled
    /// 10% toward the darkened colour's own gray so the hue calms rather
    /// than just dims -- same hue family, so metric identity (a red
    /// Recovery reads as red in both appearances) is unchanged, only the
    /// vividness that reads as "toy-like" against white is toned down.
    private static func adaptiveMetric(_ dark: (Double, Double, Double)) -> Color {
        let dimmed = (dark.0 * 0.82, dark.1 * 0.82, dark.2 * 0.82)
        let gray = (dimmed.0 + dimmed.1 + dimmed.2) / 3
        let light = (
            dimmed.0 * 0.90 + gray * 0.10,
            dimmed.1 * 0.90 + gray * 0.10,
            dimmed.2 * 0.90 + gray * 0.10
        )
        return adaptive(dark: dark, light: light)
    }

    enum Metric {
        /// Recovery bands. Green / amber / red, the convention every recovery
        /// product shares — breaking it would cost more in comprehension than
        /// any originality gains.
        static let recoveryHigh = Theme.adaptiveMetric((0.00, 0.878, 0.561))
        static let recoveryMid = Theme.adaptiveMetric((1.00, 0.761, 0.294))
        static let recoveryLow = Theme.adaptiveMetric((1.00, 0.302, 0.427))

        static let strain = Theme.adaptiveMetric((0.290, 0.659, 1.00))
        static let sleep = Theme.adaptiveMetric((0.482, 0.380, 1.00))
        static let battery = Theme.adaptiveMetric((0.153, 0.851, 0.753))
        static let hrv = Theme.adaptiveMetric((1.00, 0.435, 0.780))
        static let heart = Theme.adaptiveMetric((1.00, 0.365, 0.365))
        static let respiratory = Theme.adaptiveMetric((0.478, 0.827, 1.00))
        static let temperature = Theme.adaptiveMetric((1.00, 0.600, 0.310))
        static let oxygen = Theme.adaptiveMetric((0.400, 0.780, 1.00))
    }

    // MARK: - Semantic families (V8)
    //
    // One colour per *intelligence family*, so a concept keeps its hue from
    // Today through Sleep, Insights, Coach and the widgets. Where an existing
    // `Metric` hue already carried that meaning it is aliased here rather
    // than redefined -- nothing already drawn changes colour silently, and
    // there is exactly one place to change it if it ever should.
    //
    // Two rules the palette enforces by construction:
    //  * `attention` and `deviation` are muted amber and soft coral. There is
    //    deliberately no saturated warning red: normal physiological
    //    variation is not an alarm.
    //  * `energy` is a gradient, not a colour, because energy is a curve.
    enum Family {
        /// Sleep duration, stages, timing. Indigo / moon-blue.
        static let sleep = Metric.sleep
        /// Recovery, HRV-as-readiness. Emerald.
        static let recovery = Metric.recoveryHigh
        /// Circadian timing, body clock, daylight. Warm amber / sunrise.
        static let circadian = Metric.temperature
        /// Respiration, breathing disturbances, SpO2. Aqua.
        static let breathing = Metric.respiratory
        /// Resting HR, HRV-as-signal, wrist temperature. Soft lavender.
        static let bodySignals = Theme.adaptiveMetric((0.70, 0.62, 0.96))
        /// Something worth a look, not a warning. Muted amber.
        static let attention = Metric.recoveryMid
        /// A meaningful departure from personal baseline. Soft coral.
        static let deviation = Theme.adaptiveMetric((1.00, 0.48, 0.44))

        /// Electric blue at wake → warm gold at the day's peak. Used as a
        /// stroke/fill along the x-axis of anything that draws a day.
        static var energy: LinearGradient {
            LinearGradient(
                colors: [Metric.strain, Theme.adaptiveMetric((1.00, 0.82, 0.36))],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        /// The hue Sleep Intelligence bands resolve to. Poor/fair are
        /// attention-coloured, never red; good/excellent are the sleep hue and
        /// recovery hue so a strong night reads as calm rather than as a
        /// green tick.
        static func sleepIntelligence(_ band: SleepIntelligenceScore.Band) -> Color {
            switch band {
            case .poor: deviation
            case .fair: attention
            case .good: sleep
            case .excellent: recovery
            }
        }
    }

    /// Sleep stage colours, dark → light, matching the depth they represent.
    enum Stage {
        static let deep = Color(red: 0.294, green: 0.235, blue: 0.780)
        static let rem = Color(red: 0.545, green: 0.400, blue: 1.00)
        static let core = Color(red: 0.290, green: 0.600, blue: 0.980)
        static let awake = Color(red: 1.00, green: 0.624, blue: 0.263)
        static let unspecified = Color(red: 0.345, green: 0.741, blue: 0.808)

        static func color(for stage: SleepStage) -> Color {
            switch stage {
            case .deep: deep
            case .rem: rem
            case .core: core
            case .awake: awake
            case .unspecified: unspecified
            case .inBed: Color.primary.opacity(0.18)
            }
        }
    }

    // MARK: - Scales

    static func recoveryColor(_ percent: Double) -> Color {
        switch percent {
        case ..<34: Metric.recoveryLow
        case 34..<67: Metric.recoveryMid
        default: Metric.recoveryHigh
        }
    }

    /// Gradient for a recovery arc — a single flat colour on a ring reads as
    /// cheap; the shift across the sweep is what makes it feel alive.
    static func recoveryGradient(_ percent: Double) -> AngularGradient {
        let base = recoveryColor(percent)
        return AngularGradient(
            colors: [base.opacity(0.55), base, base.opacity(0.95)],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    static func batteryColor(_ level: Double) -> Color {
        switch level {
        case ..<25: Metric.recoveryLow
        case 25..<50: Metric.recoveryMid
        case 50..<75: Metric.battery
        default: Metric.recoveryHigh
        }
    }

    // MARK: - Type
    //
    // Text scales with the reader's Dynamic Type setting. A fixed
    // `.system(size: 13)` ignores that setting completely — which in a health
    // app is not a rough edge but a defect, since the people most likely to
    // enlarge text are the people most likely to be reading it about their own
    // health.
    //
    // The mechanism is text styles. `relativeTo:` exists only on `Font.custom`;
    // for system fonts the scaling comes from asking for `.footnote` rather
    // than for 13 points, so `style(for:)` maps the point sizes this app was
    // written with onto the nearest style. Sizes shift by a point or two in
    // places — that is the cost of the text actually responding to the setting,
    // and it is worth paying.

    /// Maps a point size onto the nearest built-in text style.
    static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11: .caption2
        case ..<13: .caption
        case ..<15: .footnote
        case ..<17: .subheadline
        case ..<20: .body
        case ..<24: .title3
        case ..<30: .title2
        default: .title
        }
    }

    /// Big display numerals — a recovery percentage, a night's duration.
    ///
    /// Deliberately **not** scaled, and the only thing here that isn't. These
    /// run from 26 to 52 points, already several times body size and legible
    /// well past any setting that would help; and each one sits inside a ring
    /// or a fixed frame that growth would break rather than improve. Scaling
    /// the text around them is what actually helps someone who needs it.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// Body and caption text.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(style(for: size), design: .default, weight: weight)
    }

    /// Rounded labels — the app's secondary voice.
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(style(for: size), design: .rounded, weight: weight)
    }

    // MARK: - Data hierarchy (V8)
    //
    // Four named levels so every screen ranks its numbers the same way. A
    // reader should be able to tell which number matters most from weight
    // and size alone, before reading a single label.

    /// Level 1 — the one number the screen exists to show. Large, calm,
    /// light-weight so it reads as a value rather than a shout.
    static let heroNumeral: Font = .system(size: 72, weight: .light, design: .rounded)

    /// Level 2 — what the hero number *means*: "GOOD", "Strong recovery".
    /// Tracked uppercase in the caller via `.tracking(1.2)`.
    static let meaning: Font = .system(.footnote, design: .rounded, weight: .semibold)

    /// Level 3 — supporting values under the hero: "7h 42m", "Need 8h 14m".
    static let supportingValue: Font = .system(.title3, design: .rounded, weight: .semibold)

    /// Level 3 label — the word under a supporting value.
    static let supportingLabel: Font = .system(.caption, design: .rounded, weight: .medium)

    /// Level 4 — evidence and detail. Deliberately the system caption so it
    /// never competes with the numbers.
    static let evidence: Font = .caption

    /// Editorial kicker above a block of prose ("YOUR MORNING BRIEF"). Pair
    /// with `.tracking(1.0)` and `.foregroundStyle(.secondary)`.
    static let kicker: Font = .system(.caption2, design: .rounded, weight: .bold)

    // MARK: - Layout

    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 18
    static let stackSpacing: CGFloat = 14
}

// MARK: - Card

/// Glass card over the night gradient.
///
/// This view is instantiated over a hundred times across the app (every
/// card on every screen), so per-instance rendering cost multiplies fast --
/// worth being deliberate about below.
struct GlassCard: ViewModifier {
    var padding: CGFloat = Theme.cardPadding

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    // .ultraThinMaterial reads as glass against Dark's near-black
                    // ground, but against Light's pale lavender it barely differs
                    // from the background it's supposed to separate from -- the
                    // "cheap, washed-out card" look. .regularMaterial is denser
                    // and holds its own shape against a pale ground the way
                    // ultraThin does against a dark one.
                    .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .fill(Theme.cardFill)
                    }
                    .overlay {
                        // Liquid Glass sheen: a soft highlight that fades from
                        // the top edge toward the middle, the way light catches
                        // the curved top of a real glass surface.
                        //
                        // Plain alpha overlay, not `.blendMode(.plusLighter)`:
                        // a blend mode forces this layer into its own offscreen
                        // render pass, and at ~0.10 peak opacity over Dark's
                        // near-black ground, additive and normal alpha blending
                        // are visually indistinguishable -- so the extra
                        // compositing pass was pure cost. With 100+ of these on
                        // screen across the app, that cost was the whole app
                        // measurably laggier, which is what an ordinary overlay
                        // fixes without giving up the highlight.
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.glassHighlight(0.10), Theme.glassHighlight(0)],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.45)
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1)
                    }
            }
            // Flattens the padded content + four stacked background layers
            // into one rasterized layer before the shadow below is computed.
            // Without this, `.shadow` has to derive a shadow from every
            // sublayer independently -- the material fill, each overlay
            // shape, and every glyph/icon in the card's own content -- which
            // is real, compounding cost multiplied by the 100+ cards on
            // screen across the app, and the actual cause a real-device
            // report traced to laggy scrolling. One flattened shadow reads
            // identically and costs a small fraction as much.
            .compositingGroup()
            .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glassCard(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(GlassCard(padding: padding))
    }

    /// Caps Dynamic Type growth to a size the card layouts survive.
    ///
    /// Applied once per screen alongside the background, rather than per view.
    /// Raised from `.accessibility1` to `.accessibility3` (~215% of default):
    /// the app has no on-device or screenshot-based visual verification in
    /// this CI-only environment, so removing the cap entirely is not something
    /// that can be honestly claimed as verified here. `.accessibility3` is a
    /// real, substantial increase for anyone who needs it while staying inside
    /// a range where `.fixedSize(horizontal:false, vertical:true)` and
    /// scrolling containers (already used throughout) still hold up against
    /// the fixed-height stat rows that clip first. Fully removing the cap is
    /// the honest next step, gated on either a visual-regression harness or
    /// a real-device pass — see task tracking `accessibility5`.
    func zoonTypography() -> some View {
        // V8: cap raised from `.accessibility3` to the full range. The rows
        // that used to clip first (Today's metric cluster, Health Pulse
        // tiles, the two-time Autopilot headline) have all been rebuilt on
        // `AdaptiveStack`/`ViewThatFits` so they reflow instead of
        // truncating, and the hero numeral is the one deliberately fixed
        // size in the app (see `Theme.numeral`). Screens not yet rebuilt
        // scroll; nothing is unreachable at `.accessibility5`.
        dynamicTypeSize(...DynamicTypeSize.accessibility5)
    }

    /// The V8 alternative to `.glassCard()`: content that sits directly on
    /// the page, separated from its neighbours by a hairline rather than by
    /// a rounded container. Use this for a visualization or a typographic
    /// block; keep `.glassCard()` for things that genuinely are a container
    /// (an input control, a grouped set of toggles).
    func pageSection(topRule: Bool = true) -> some View {
        modifier(PageSection(topRule: topRule))
    }

    /// Applies the app's night background behind a scrolling screen.
    ///
    /// Also applies the Dynamic Type cap, because this modifier already marks
    /// every screen root in the app — attaching it here means a new screen
    /// cannot forget it, which is the failure mode of a rule that has to be
    /// remembered.
    func nightBackground() -> some View {
        zoonTypography()
        .background {
            ZStack(alignment: .top) {
                Theme.background
                Theme.heroGlow
            }
            .ignoresSafeArea()
        }
    }

    /// Time-of-day-aware ground, for screens (the Today hero in particular)
    /// that want the redesign spec's "Dynamic Background System" instead of
    /// the flat `nightBackground()`. Also applies the Dynamic Type cap for
    /// the same reason `nightBackground()` does.
    func ambientBackground() -> some View {
        zoonTypography()
        .background { ZoonAmbientBackground() }
    }
}

/// Picks the ground from `Theme.morningBackground`/`dayBackground`/
/// `eveningBackground`/`background` (night) by wall-clock hour.
///
/// Deliberately *not* a continuously-animating gradient -- the spec warns
/// against exactly that, and an unbounded animation behind a screen used a
/// hundred times across the app would be a real, measurable battery cost for
/// a change nobody asked to see moving. The band is read once per appearance
/// (covers app launch and returning from background overnight) rather than
/// on a running timer, so there is nothing to disable for Reduce Motion --
/// there's no motion to begin with, only a value that can differ next time
/// the view appears.
struct ZoonAmbientBackground: View {
    @State private var band = Band.current()

    enum Band {
        case morning, day, evening, night

        static func current(now: Date = .now, calendar: Calendar = .current) -> Band {
            switch calendar.component(.hour, from: now) {
            case 5..<9: .morning
            case 9..<17: .day
            case 17..<21: .evening
            default: .night
            }
        }
    }

    private var gradient: LinearGradient {
        switch band {
        case .morning: Theme.morningBackground
        case .day: Theme.dayBackground
        case .evening: Theme.eveningBackground
        case .night: Theme.background
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            gradient
            Theme.heroGlow
        }
        .ignoresSafeArea()
        .onAppear { band = .current() }
    }
}

/// A stack that lays out horizontally until the reader's Dynamic Type size
/// gets big enough that side-by-side content would get cramped or truncated,
/// then reflows to vertical -- the pattern that breaks first once Dynamic
/// Type is allowed past `.accessibility1` (see `zoonTypography()` above).
///
/// Built on `AnyLayout` rather than a fixed-width breakpoint, so it responds
/// to the thing that's actually growing rather than approximating it via
/// screen size.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat?
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout: AnyLayout = dynamicTypeSize >= .accessibility1
            ? AnyLayout(VStackLayout(alignment: alignment, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            content
        }
    }
}

/// See `View.pageSection(topRule:)`.
struct PageSection: ViewModifier {
    var topRule: Bool

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if topRule {
                Rectangle()
                    .fill(Theme.cardStroke)
                    .frame(height: 1)
                    .padding(.bottom, 18)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// Editorial section heading: a small tracked uppercase kicker, optionally
/// with a trailing accessory (a "See all" link, a picker). This is the V8
/// heading for content that sits on the page; `SectionHeader` below keeps
/// serving the cards that remain.
struct ZoonSectionHeader<Accessory: View>: View {
    let title: String
    var accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

extension ZoonSectionHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.title = title
        self.accessory = EmptyView()
    }
}

/// Small pill used for statuses and tags.
struct StatusPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.text(10, weight: .bold))
            }
            Text(text)
                .font(Theme.label(11))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .zoonGlassPill(tint: tint)
        .foregroundStyle(tint)
    }
}

/// Section heading used across screens.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    /// A custom `ZoonIcon` mark in place of an SF Symbol, for sections whose
    /// concept has its own icon. Takes priority over `systemImage` when both
    /// are set; existing call sites pass only `systemImage` and are
    /// unaffected.
    var icon: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let icon {
                    icon
                        .frame(width: 13, height: 13)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(Theme.label(16, weight: .bold))
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
