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
