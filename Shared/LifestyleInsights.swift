import Foundation

/// A day's measured lifestyle signals from HealthKit -- caffeine, alcohol,
/// daylight, and mindfulness -- read directly rather than relying on the
/// Journal's manual tags for behaviours a wearable or a logging app can
/// often measure on its own.
///
/// Entirely opt-in (see `HealthKitManager.requestLifestyleInsightsAuthorization`)
/// and purely additive: this never overwrites or disables manual Journal
/// tagging, it's a second, measured source shown alongside it. All four
/// fields are independently optional -- someone may log meals in a
/// caffeine-tracking app but never use Mindfulness sessions, and a day with
/// no samples for one type shouldn't read as "zero", which would claim more
/// precision than a missing reading actually supports.
struct LifestyleInsights: Codable, Hashable, Sendable {
    let caffeineMg: Double?
    let alcoholicBeverages: Double?
    let daylightMinutes: Double?
    let mindfulMinutes: Double?

    var isEmpty: Bool {
        caffeineMg == nil && alcoholicBeverages == nil && daylightMinutes == nil && mindfulMinutes == nil
    }
}
