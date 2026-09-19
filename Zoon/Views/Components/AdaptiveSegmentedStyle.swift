import SwiftUI

/// Segmented below accessibility text sizes, a menu at and above them.
///
/// The AX5 capture of Insights is what raised this. Everything on that screen
/// scales -- a 40-point headline, a 60-point numeral, day initials -- while
/// the "2 Weeks / Month / Quarter" control that selects what all of it
/// *means* stays at roughly 11 points. It is the one thing on the screen
/// somebody with low vision cannot read, and it is the control.
///
/// This is not a cap the app applied. `UISegmentedControl` limits its own
/// label size by design: three segments abreast have a fixed width to share,
/// and letting the text grow would clip it instead. So the fix is not to
/// scale the segments -- there is genuinely no room -- but to stop being
/// segmented when the text no longer fits that shape. A menu picker shows the
/// current selection on one line, scales with the setting like everything
/// around it, opens a list with full-size rows, and carries a system-sized
/// hit target.
///
/// The same reasoning as `FloatingTabBar`: at accessibility sizes the layout
/// changes rather than the type being held down. The audit's line is that
/// accessibility is a layout requirement, and "fix important text by capping
/// it" is the thing it warns against.
///
/// Below accessibility sizes nothing changes -- segmented is the right
/// control there, and it is what every screenshot and UI test already
/// exercises.
private struct AdaptiveSegmentedStyle: ViewModifier {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.pickerStyle(.menu)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

extension View {

    /// Use in place of `.pickerStyle(.segmented)` so the control reflows at
    /// accessibility sizes instead of staying small beside text that grew.
    func adaptiveSegmentedStyle() -> some View {
        modifier(AdaptiveSegmentedStyle())
    }
}
