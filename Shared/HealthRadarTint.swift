import SwiftUI

/// The one mapping from the radar's state to a colour.
///
/// Separate from `HealthRadar` so the engine stays Foundation-only and its
/// state machine is testable without SwiftUI. Every radar surface — Today,
/// the detail view, the pulse strip, the intelligence grid, the watch — reads
/// its colour from here, so none of them can decide independently that an
/// empty signal list looks green.
extension HealthRadar.State {

    var tint: Color {
        switch tone {
        // Not a verdict, so not a verdict colour. An indeterminate state
        // painted green is the false reassurance in a different medium.
        case .neutral: Theme.inkSecondary
        case .good: Theme.Metric.recoveryHigh
        case .caution: Theme.Family.attention
        case .alert: Theme.Family.deviation
        }
    }
}
