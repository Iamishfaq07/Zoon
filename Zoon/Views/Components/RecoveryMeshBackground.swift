import SwiftUI

/// iOS 18 mesh whose palette and motion follow Recovery.
///
/// Slow indigo–cyan above 85, a quiet teal in the middle, and a faster
/// amber–red pulse below 40. Reduce Motion freezes the control points: the
/// colour still reflects the score, the mesh does not breathe.
///
/// Light is a dawn wash of the same families, not Dark's navy at a lower
/// opacity. The mesh is Today's entire ground; Dark fills under Light's
/// dark text made the whole screen unreadably blank.
struct RecoveryMeshBackground: View {
    var recoveryPercent: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var palette: [Color] {
        let light = colorScheme == .light
        switch recoveryPercent {
        case 85...:
            light ? Self.lightHigh : Self.darkHigh
        case 40..<85:
            light ? Self.lightMid : Self.darkMid
        default:
            light ? Self.lightLow : Self.darkLow
        }
    }

    /// Seconds per full cycle. High recovery breathes slowly; low recovery
    /// is restlessness, not decoration.
    private var period: Double {
        switch recoveryPercent {
        case 85...: 14
        case 40..<85: 9
        default: 5
        }
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                if reduceMotion {
                    mesh(phase: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { timeline in
                        mesh(phase: timeline.date.timeIntervalSinceReferenceDate / period)
                    }
                }
            } else {
                LinearGradient(colors: [palette[0], palette[4], palette[8]], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    @available(iOS 18.0, *)
    private func mesh(phase: Double) -> some View {
        let t = (phase - floor(phase)) * 2 * Double.pi
        let drift = SIMD2<Float>(Float(sin(t) * 0.04), Float(cos(t * 0.7) * 0.04))
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], SIMD2<Float>(0.5, 0.5) + drift, [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: palette
        )
    }

    // MARK: - Palettes

    private static let darkHigh: [Color] = [
        Color(red: 0.05, green: 0.08, blue: 0.22),
        Color(red: 0.10, green: 0.22, blue: 0.38),
        Color(red: 0.18, green: 0.42, blue: 0.48),
        Color(red: 0.07, green: 0.14, blue: 0.32),
        Color(red: 0.12, green: 0.28, blue: 0.44),
        Color(red: 0.22, green: 0.50, blue: 0.52),
        Color(red: 0.04, green: 0.06, blue: 0.16),
        Color(red: 0.08, green: 0.16, blue: 0.30),
        Color(red: 0.14, green: 0.34, blue: 0.42)
    ]

    private static let darkMid: [Color] = [
        Color(red: 0.07, green: 0.09, blue: 0.20),
        Color(red: 0.14, green: 0.18, blue: 0.32),
        Color(red: 0.20, green: 0.28, blue: 0.38),
        Color(red: 0.10, green: 0.16, blue: 0.28),
        Color(red: 0.18, green: 0.24, blue: 0.34),
        Color(red: 0.24, green: 0.32, blue: 0.40),
        Color(red: 0.05, green: 0.07, blue: 0.16),
        Color(red: 0.12, green: 0.14, blue: 0.26),
        Color(red: 0.16, green: 0.22, blue: 0.32)
    ]

    private static let darkLow: [Color] = [
        Color(red: 0.18, green: 0.06, blue: 0.06),
        Color(red: 0.32, green: 0.14, blue: 0.08),
        Color(red: 0.42, green: 0.22, blue: 0.10),
        Color(red: 0.22, green: 0.08, blue: 0.08),
        Color(red: 0.38, green: 0.16, blue: 0.08),
        Color(red: 0.48, green: 0.24, blue: 0.10),
        Color(red: 0.12, green: 0.04, blue: 0.06),
        Color(red: 0.28, green: 0.10, blue: 0.08),
        Color(red: 0.36, green: 0.16, blue: 0.08)
    ]

    /// Lunar dawn: the same indigo–cyan family lifted onto the pearl ground
    /// so primary/secondary text still clears WCAG AA.
    private static let lightHigh: [Color] = [
        Color(red: 0.93, green: 0.95, blue: 0.98),
        Color(red: 0.84, green: 0.91, blue: 0.96),
        Color(red: 0.78, green: 0.90, blue: 0.93),
        Color(red: 0.90, green: 0.94, blue: 0.97),
        Color(red: 0.80, green: 0.90, blue: 0.94),
        Color(red: 0.72, green: 0.87, blue: 0.90),
        Color(red: 0.96, green: 0.96, blue: 0.97),
        Color(red: 0.88, green: 0.93, blue: 0.96),
        Color(red: 0.82, green: 0.91, blue: 0.94)
    ]

    private static let lightMid: [Color] = [
        Color(red: 0.95, green: 0.95, blue: 0.97),
        Color(red: 0.90, green: 0.92, blue: 0.96),
        Color(red: 0.86, green: 0.89, blue: 0.94),
        Color(red: 0.93, green: 0.94, blue: 0.97),
        Color(red: 0.88, green: 0.90, blue: 0.95),
        Color(red: 0.84, green: 0.87, blue: 0.93),
        Color(red: 0.97, green: 0.97, blue: 0.98),
        Color(red: 0.91, green: 0.92, blue: 0.96),
        Color(red: 0.87, green: 0.89, blue: 0.94)
    ]

    private static let lightLow: [Color] = [
        Color(red: 0.98, green: 0.94, blue: 0.91),
        Color(red: 0.97, green: 0.88, blue: 0.82),
        Color(red: 0.96, green: 0.84, blue: 0.76),
        Color(red: 0.97, green: 0.91, blue: 0.87),
        Color(red: 0.96, green: 0.86, blue: 0.78),
        Color(red: 0.95, green: 0.82, blue: 0.72),
        Color(red: 0.98, green: 0.95, blue: 0.93),
        Color(red: 0.96, green: 0.89, blue: 0.84),
        Color(red: 0.95, green: 0.85, blue: 0.78)
    ]
}
