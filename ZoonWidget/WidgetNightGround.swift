import SwiftUI
import WidgetKit

/// Midnight navy on the Home Screen; system material on Lock Screen families
/// so redaction and tint still work.
struct WidgetNightGround: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            AccessoryWidgetBackground()
        default:
            Color(red: 6 / 255, green: 8 / 255, blue: 17 / 255)
        }
    }
}

extension View {
    /// The widget's ground, and the appearance that goes with it.
    ///
    /// The Home Screen ground is always midnight navy, but the text styles
    /// -- `.primary`, `.secondary`, the adaptive metric tints -- followed the
    /// system appearance. On a phone in Light mode, the default, the insight
    /// sentence and the stat values were black on navy and the labels grey
    /// at about 1.3:1. Home Screen families are drawn dark to match the
    /// ground; Lock Screen families keep the system's own appearance, so
    /// vibrancy and tinting still work.
    func zoonWidgetChrome() -> some View {
        modifier(ZoonWidgetChrome())
    }
}

private struct ZoonWidgetChrome: ViewModifier {
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    func body(content: Content) -> some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            content.containerBackground(for: .widget) { WidgetNightGround() }
        default:
            content
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { WidgetNightGround() }
        }
    }
}
