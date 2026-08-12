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
                adaptive(dark: (0.024, 0.031, 0.078), light: (0.902, 0.914, 0.965)),
                adaptive(dark: (0.051, 0.063, 0.141), light: (0.925, 0.925, 0.976)),
                adaptive(dark: (0.078, 0.063, 0.200), light: (0.949, 0.925, 0.976))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Subtle top-glow used behind hero content.
    static var heroGlow: RadialGradient {
        RadialGradient(
            colors: [adaptive(dark: (0.35, 0.30, 0.95), light: (0.55, 0.50, 0.95)).opacity(0.35), .clear],
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
    private static func adaptive(
        dark: (Double, Double, Double),
        light: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
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

    /// A hardcoded white overlay reads as a hairline in Dark and is nearly
    /// invisible against a light card in Light -- glass needs a dark edge to
    /// read as glass once the surface behind it is pale rather than black.
    static var cardStroke: Color { adaptive(dark: (1, 1, 1), light: (0, 0, 0)).opacity(0.08) }
    static var cardFill: Color { adaptive(dark: (1, 1, 1), light: (0, 0, 0)).opacity(0.05) }

    // MARK: - Metric hues

    enum Metric {
        /// Recovery bands. Green / amber / red, the convention every recovery
        /// product shares — breaking it would cost more in comprehension than
        /// any originality gains.
        static let recoveryHigh = Color(red: 0.00, green: 0.878, blue: 0.561)
        static let recoveryMid = Color(red: 1.00, green: 0.761, blue: 0.294)
        static let recoveryLow = Color(red: 1.00, green: 0.302, blue: 0.427)

        static let strain = Color(red: 0.290, green: 0.659, blue: 1.00)
        static let sleep = Color(red: 0.482, green: 0.380, blue: 1.00)
        static let battery = Color(red: 0.153, green: 0.851, blue: 0.753)
        static let hrv = Color(red: 1.00, green: 0.435, blue: 0.780)
        static let heart = Color(red: 1.00, green: 0.365, blue: 0.365)
        static let respiratory = Color(red: 0.478, green: 0.827, blue: 1.00)
        static let temperature = Color(red: 1.00, green: 0.600, blue: 0.310)
        static let oxygen = Color(red: 0.400, green: 0.780, blue: 1.00)
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
            case .inBed: Color.white.opacity(0.18)
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

    // MARK: - Layout

    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 18
    static let stackSpacing: CGFloat = 14
}

// MARK: - Card

/// Glass card over the night gradient.
struct GlassCard: ViewModifier {
    var padding: CGFloat = Theme.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .fill(Theme.cardFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1)
                    }
            }
    }
}

extension View {
    func glassCard(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(GlassCard(padding: padding))
    }

    /// Caps Dynamic Type growth to a size the card layouts survive.
    ///
    /// Applied once per screen alongside the background, rather than per view.
    /// `.accessibility1` is roughly 150% of default — a genuine improvement for
    /// anyone who needs it, and the point at which the fixed-height rows in
    /// this app begin to clip rather than reflow. Removing those fixed heights
    /// would let the cap go higher, and is the honest next step.
    func zoonTypography() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
        .background(tint.opacity(0.18), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Section heading used across screens.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let systemImage {
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
