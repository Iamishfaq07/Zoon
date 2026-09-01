import SwiftUI

/// The one horizontal scrub gesture every hand-drawn V8 chart shares.
///
/// Swift Charts gives `chartXSelection` for free; a `Canvas` or a
/// `GeometryReader`-built visual has to do the touch-to-fraction math by
/// hand, and before this each of them did -- the hypnogram, the energy
/// horizon and the orb each carried their own copy with slightly different
/// hit slop and haptic rules. This owns that once:
///
/// * `fraction` is the finger's position as 0...1 across the width, `nil`
///   when lifted (callers show a cursor while non-nil).
/// * `detent` is an optional integer bucket the caller derives from the
///   fraction (a stage segment index, an hour); the scrubber fires one soft
///   haptic each time the bucket changes and never per pixel.
/// * Reduce Motion is respected by the caller's animation, not here -- the
///   gesture itself must always work.
///
/// The hit target is the whole overlaid rectangle, so a chart 40pt tall
/// is as easy to scrub as one 200pt tall.
struct ZoonChartScrubber: ViewModifier {
    @Binding var fraction: CGFloat?
    /// Maps a fraction to a haptic bucket. Return `nil` to disable haptics.
    var detent: ((CGFloat) -> Int?)?
    /// Called once when the finger lifts, with the last fraction. Lets a
    /// caller keep a selection sticky (tap-to-select) rather than clearing it.
    var onEnd: ((CGFloat?) -> Void)?
    /// Whether lifting the finger clears the selection. `true` for
    /// inspect-while-dragging readouts; `false` for pick-and-stay controls.
    var clearsOnEnd: Bool = true

    @State private var lastDetent: Int?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let width = max(geo.size.width, 1)
                                    let next = min(1, max(0, value.location.x / width))
                                    fraction = next
                                    if let detent, let bucket = detent(next), bucket != lastDetent {
                                        if lastDetent != nil { Haptics.scrubDetent() }
                                        lastDetent = bucket
                                    }
                                }
                                .onEnded { _ in
                                    onEnd?(fraction)
                                    if clearsOnEnd { fraction = nil }
                                    lastDetent = nil
                                }
                        )
                }
            }
    }
}

extension View {
    /// See `ZoonChartScrubber`.
    func zoonScrubbable(
        fraction: Binding<CGFloat?>,
        detent: ((CGFloat) -> Int?)? = nil,
        clearsOnEnd: Bool = true,
        onEnd: ((CGFloat?) -> Void)? = nil
    ) -> some View {
        modifier(ZoonChartScrubber(fraction: fraction, detent: detent, onEnd: onEnd, clearsOnEnd: clearsOnEnd))
    }
}

/// The vertical hairline every scrubbable chart shows under the finger.
/// Drawn as a view rather than inside each `Canvas` so it sits above any
/// overlay marks and animates independently of the chart's draw-in.
struct ScrubCursor: View {
    let fraction: CGFloat
    var tint: Color = .primary

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(tint.opacity(0.45))
                .frame(width: 1)
                .offset(x: geo.size.width * fraction - 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Positions a readout badge above a scrub cursor without letting it run off
/// either edge of the chart -- the same clamping math three charts used to
/// duplicate inline.
struct ScrubReadoutPlacement: ViewModifier {
    let fraction: CGFloat
    let badgeWidth: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .offset(x: min(max(0, geo.size.width * fraction - badgeWidth / 2), geo.size.width - badgeWidth))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func scrubReadoutPlacement(fraction: CGFloat, badgeWidth: CGFloat = 120) -> some View {
        modifier(ScrubReadoutPlacement(fraction: fraction, badgeWidth: badgeWidth))
    }
}
