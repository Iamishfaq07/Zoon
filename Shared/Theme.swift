import SwiftUI

/// Zoon's visual language.
///
/// Dark-first by intention, not fashion: this is an app you open at 7am in a
/// dark bedroom and glance at on a lock screen at night. A light-first palette
/// inverted for dark mode would be the wrong way round.
///
/// Colours are declared as explicit sRGB rather than system semantic colours
/// because the metric hues carry meaning (a red recovery must read as *red*,
/// consistently, in both appearances and in a screenshot). Text and chrome still
/// use system materials so Dynamic Type, contrast settings, and vibrancy come
/// for free.
enum Theme {

    // MARK: - Surfaces

    /// Deep night gradient — the app's ground. "Zoon" means moon; the palette
    /// is the sky around it.
    static let background = LinearGradient(
        colors: [
            Color(red: 0.024, green: 0.031, blue: 0.078),
            Color(red: 0.051, green: 0.063, blue: 0.141),
            Color(red: 0.078, green: 0.063, blue: 0.200)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Subtle top-glow used behind hero content.
    static let heroGlow = RadialGradient(
        colors: [Color(red: 0.35, green: 0.30, blue: 0.95).opacity(0.35), .clear],
        center: .top,
        startRadius: 10,
        endRadius: 420
    )

    static let cardStroke = Color.white.opacity(0.08)
    static let cardFill = Color.white.opacity(0.05)

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

    /// Big numerals. Rounded + monospaced digits so values don't jitter as they
    /// animate.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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

    /// Applies the app's night background behind a scrolling screen.
    func nightBackground() -> some View {
        background {
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
                    .font(.system(size: 10, weight: .bold))
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
                        .font(.system(size: 12, weight: .semibold))
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
