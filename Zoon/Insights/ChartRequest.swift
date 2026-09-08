import Foundation

enum ChartMetric: String, CaseIterable, Codable, Identifiable {
    case sleepDuration, efficiency, hrv, bedtime
    var id: String { rawValue }
    var label: String { switch self { case .sleepDuration: "Sleep duration"; case .efficiency: "Efficiency"; case .hrv: "HRV"; case .bedtime: "Bedtime" } }
}

struct ChartRequest: Equatable {
    var metric: ChartMetric
    var days: Int = 30
    var groupedWeekly: Bool = false
}

enum ChartRequestParser {
    static func parse(_ text: String) -> ChartRequest? {
        let value = text.lowercased()
        let metric: ChartMetric
        if value.contains("hrv") || value.contains("heart rate variability") { metric = .hrv }
        else if value.contains("efficiency") { metric = .efficiency }
        else if value.contains("bedtime") || value.contains("sleep time") { metric = .bedtime }
        else if value.contains("duration") || value.contains("hours") || value.contains("sleep") { metric = .sleepDuration }
        else { return nil }
        let days = [365, 180, 90, 30, 14, 7].first { value.contains("\($0)") } ?? 30
        return ChartRequest(metric: metric, days: days, groupedWeekly: value.contains("week") || value.contains("weekly"))
    }
}
