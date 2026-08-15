import Foundation

/// A week in review.
///
/// Whoop's Weekly Performance Assessment and Garmin's Morning Report both work
/// because a week is the shortest window where behaviour is visible above noise.
/// A single night tells you almost nothing you can act on; seven of them show
/// you your actual habits.
struct WeeklyReport {

    let periodStart: Date
    let periodEnd: Date
    let nightCount: Int

    let averageRecovery: Double?
    let averageSleepPerformance: Double?
    let averageSleepMinutes: Double?
    let averageHRV: Double?
    let averageRestingHR: Double?
    let totalStrain: Double?

    /// Change vs the previous seven days, as signed percentages.
    let recoveryTrend: Double?
    let sleepTrend: Double?
    let hrvTrend: Double?

    let bestNight: SleepNightFeatures?
    let worstNight: SleepNightFeatures?

    let consistencyMinutes: Double?
    let goalHitCount: Int
    let highlights: [Highlight]

    struct Highlight: Identifiable, Hashable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
        let tone: Tone

        enum Tone: Hashable {
            case positive, neutral, caution
        }
    }

    // MARK: - Build

    static func build(
        nights: [SleepNightFeatures],
        recoveries: [Date: Int],
        previousNights: [SleepNightFeatures],
        previousRecoveries: [Date: Int],
        goalMinutes: Double,
        consistencyMinutes: Double?
    ) -> WeeklyReport {

        let sorted = nights.sorted { $0.date < $1.date }
        let start = sorted.first?.date ?? .now
        let end = sorted.last?.date ?? .now

        let recoveryValues = sorted.compactMap { recoveries[$0.date].map(Double.init) }
        let previousRecoveryValues = previousNights.compactMap { previousRecoveries[$0.date].map(Double.init) }

        let avgRecovery = mean(recoveryValues)
        let avgSleep = mean(sorted.map(\.timeAsleepMinutes))
        let avgHRV = mean(sorted.compactMap(\.avgHRV))
        // True RHR (see SleepNightFeatures.restingHeartRate), not the
        // sleep-window low -- this is displayed labeled "Resting HR".
        let avgRHR = mean(sorted.compactMap(\.restingHeartRate))

        let sleepPerformances = sorted.map { min(100, $0.timeAsleepMinutes / max(goalMinutes, 1) * 100) }
        let avgPerformance = mean(sleepPerformances)

        let goalHits = sorted.filter { $0.timeAsleepMinutes >= goalMinutes }.count

        // Best/worst by sleep performance rather than raw duration — nine
        // fragmented hours is not a better night than seven clean ones.
        let ranked = sorted.sorted {
            ($0.timeAsleepMinutes * $0.sleepEfficiencyPercent) < ($1.timeAsleepMinutes * $1.sleepEfficiencyPercent)
        }

        let report = WeeklyReport(
            periodStart: start,
            periodEnd: end,
            nightCount: sorted.count,
            averageRecovery: avgRecovery,
            averageSleepPerformance: avgPerformance,
            averageSleepMinutes: avgSleep,
            averageHRV: avgHRV,
            averageRestingHR: avgRHR,
            totalStrain: nil,
            recoveryTrend: percentChange(avgRecovery, mean(previousRecoveryValues)),
            sleepTrend: percentChange(avgSleep, mean(previousNights.map(\.timeAsleepMinutes))),
            hrvTrend: percentChange(avgHRV, mean(previousNights.compactMap(\.avgHRV))),
            bestNight: ranked.last,
            worstNight: ranked.first,
            consistencyMinutes: consistencyMinutes,
            goalHitCount: goalHits,
            highlights: []
        )

        return report.withHighlights(goalMinutes: goalMinutes)
    }

    /// Derives the narrative bullets. Ordered by how much a reader would care,
    /// and capped — a report with fourteen highlights has none.
    private func withHighlights(goalMinutes: Double) -> WeeklyReport {
        var items: [Highlight] = []

        if let consistency = consistencyMinutes {
            if consistency < 30 {
                items.append(Highlight(
                    symbol: "target",
                    title: "Rock-solid schedule",
                    detail: "Your bedtime varied by only ±\(Int(consistency)) minutes. This is the single biggest lever most people never pull.",
                    tone: .positive
                ))
            } else if consistency > 75 {
                items.append(Highlight(
                    symbol: "arrow.left.arrow.right",
                    title: "Irregular bedtimes",
                    detail: "Your bedtime swung by ±\(Int(consistency)) minutes. Tightening this will do more than any supplement.",
                    tone: .caution
                ))
            }
        }

        if let trend = hrvTrend, abs(trend) >= 6 {
            items.append(Highlight(
                symbol: trend > 0 ? "arrow.up.right" : "arrow.down.right",
                title: trend > 0 ? "HRV trending up" : "HRV trending down",
                detail: trend > 0
                    ? "Up \(String(format: "%.0f%%", trend)) on the previous week — your body is adapting well to its current load."
                    : "Down \(String(format: "%.0f%%", abs(trend))) on the previous week. Often training load, stress, or alcohol.",
                tone: trend > 0 ? .positive : .caution
            ))
        }

        if nightCount > 0 {
            let ratio = Double(goalHitCount) / Double(nightCount)
            // "nights", unconditionally, read as "1 of 1 nights" on a
            // single-night week.
            let nightWord = nightCount == 1 ? "night" : "nights"
            if ratio >= 0.85 {
                items.append(Highlight(
                    symbol: "checkmark.seal.fill",
                    title: "Hit your goal \(goalHitCount) of \(nightCount) \(nightWord)",
                    detail: "Consistently meeting your sleep need is the foundation everything else sits on.",
                    tone: .positive
                ))
            } else if ratio <= 0.4 {
                items.append(Highlight(
                    symbol: "exclamationmark.circle",
                    // "only 0 of 7" isn't English -- and zero is the most
                    // common way to land in this branch, so it was also the
                    // most likely phrasing to be seen.
                    title: goalHitCount == 0
                        ? "Goal missed every night"
                        : "Goal met only \(goalHitCount) of \(nightCount) \(nightWord)",
                    detail: "You're accumulating debt faster than you're repaying it. Move bedtime earlier rather than sleeping in.",
                    tone: .caution
                ))
            }
        }

        if let trend = sleepTrend, abs(trend) >= 8 {
            items.append(Highlight(
                symbol: "bed.double.fill",
                title: trend > 0 ? "Sleeping more" : "Sleeping less",
                detail: trend > 0
                    ? "Up \(String(format: "%.0f%%", trend)) on last week."
                    : "Down \(String(format: "%.0f%%", abs(trend))) on last week.",
                tone: trend > 0 ? .positive : .caution
            ))
        }

        if let recovery = averageRecovery, items.count < 4 {
            items.append(Highlight(
                symbol: "bolt.heart.fill",
                title: "Average recovery \(Int(recovery))%",
                detail: recovery >= 60
                    ? "You spent most of the week ready to train."
                    : "You spent most of the week under-recovered. Sleep is the lever.",
                tone: recovery >= 60 ? .positive : .neutral
            ))
        }

        return WeeklyReport(
            periodStart: periodStart, periodEnd: periodEnd, nightCount: nightCount,
            averageRecovery: averageRecovery, averageSleepPerformance: averageSleepPerformance,
            averageSleepMinutes: averageSleepMinutes, averageHRV: averageHRV,
            averageRestingHR: averageRestingHR, totalStrain: totalStrain,
            recoveryTrend: recoveryTrend, sleepTrend: sleepTrend, hrvTrend: hrvTrend,
            bestNight: bestNight, worstNight: worstNight,
            consistencyMinutes: consistencyMinutes, goalHitCount: goalHitCount,
            highlights: Array(items.prefix(4))
        )
    }

    // MARK: - Helpers

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func percentChange(_ current: Double?, _ previous: Double?) -> Double? {
        guard let current, let previous, previous != 0 else { return nil }
        return (current - previous) / abs(previous) * 100
    }
}
