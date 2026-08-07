import WidgetKit
import SwiftUI

/// Widget extension entry point.
///
/// The extension deliberately depends on very little: the `Shared/` folder only.
/// It never opens SwiftData and never touches HealthKit — a widget process has a
/// small memory ceiling and gets killed without ceremony when it exceeds it, and
/// running the extraction pipeline there would be a good way to find that out in
/// production. It reads one small JSON snapshot the app writes.
@main
struct ZoonWidgetBundle: WidgetBundle {
    var body: some Widget {
        SleepDebtWidget()
        SleepScoreWidget()
    }
}
