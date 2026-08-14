import SwiftUI

/// Native Liquid Glass adoption, gated by OS availability.
///
/// The existing `.background(tint.opacity(...), in: Capsule())` approximation
/// stays as the fallback everywhere -- this only swaps in the real system
/// material where SwiftUI actually exposes `glassEffect` (iOS/watchOS 26+),
/// following the same `#available` gating this codebase already uses for
/// other iOS 26 APIs (`WakeAlarm`, `FoundationModelInsightEngine`). Per the
/// redesign spec, native glass is for small floating elements -- pills,
/// chips, floating controls -- not applied everywhere `.glassCard()` is used
/// today.
extension View {
    /// A pill-shaped glass background tinted with a metric colour, used for
    /// `StatusPill` and other small floating tags.
    @ViewBuilder
    func zoonGlassPill(tint: Color) -> some View {
        if #available(iOS 26.0, watchOS 26.0, *) {
            glassEffect(.regular.tint(tint.opacity(0.35)), in: .capsule)
        } else {
            background(tint.opacity(0.18), in: Capsule())
        }
    }
}
