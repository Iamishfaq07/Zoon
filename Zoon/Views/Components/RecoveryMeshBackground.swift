import SwiftUI

/// iOS 18 mesh whose palette and motion follow Recovery.
///
/// Slow indigo–cyan above 85, a quiet teal in the middle, and a faster
/// amber–red pulse below 40. Reduce Motion freezes the control points: the
/// colour still reflects the score, the mesh does not breathe.
struct RecoveryMeshBackground: View {
    var recoveryPercent: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: [Color] {
        switch recoveryPercent {
        case 85...:
            [
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
        case 40..<85:
            [
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
        default:
            [
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
}
