import Foundation

/// Personal nap associations, observational only.
///
/// Nap Coach's rules stay. This layer watches *this person's* naps against
/// the night that followed and, with enough samples, says things like
/// "your 20–30 minute naps before 3 PM have not usually shifted bedtime."
/// It never claims a nap caused a later night.
enum NapLearning {

    struct Observation: Hashable, Sendable {
        let napStartHour: Double
        let napMinutes: Double
        let bedtimeHour: Double
        let latencyMinutes: Double?
        let nextAsleepMinutes: Double?
        let nextRecoveryPercent: Double?
    }

    struct Finding: Hashable, Sendable {
        let sentence: String
        let sampleCount: Int
        let confidence: MetricConfidence
    }

    static let minimumSamples = 6

    static func findings(from naps: [Observation]) -> [Finding] {
        guard naps.count >= minimumSamples else {
            return [Finding(
                sentence: "Zoon has \(naps.count) logged nap\(naps.count == 1 ? "" : "s"). Associations with tonight start after \(minimumSamples).",
                sampleCount: naps.count,
                confidence: .insufficient
            )]
        }

        var out: [Finding] = []

        let shortEarly = naps.filter { $0.napMinutes <= 30 && $0.napStartHour < 15 }
        if shortEarly.count >= minimumSamples {
            let laterBed = shortEarly.filter { $0.bedtimeHour >= 0.5 && $0.bedtimeHour < 6 }.count
            if Double(laterBed) / Double(shortEarly.count) < 0.35 {
                out.append(Finding(
                    sentence: "Your 20–30 minute naps before 3 PM have not usually sat alongside a later bedtime.",
                    sampleCount: shortEarly.count,
                    confidence: shortEarly.count >= 12 ? .moderate : .low
                ))
            }
        }

        let longEvening = naps.filter { $0.napMinutes >= 45 && $0.napStartHour >= 15 }
        if longEvening.count >= minimumSamples {
            let lateOnset = longEvening.compactMap(\.latencyMinutes)
            let rest = naps.filter { !($0.napMinutes >= 45 && $0.napStartHour >= 15) }.compactMap(\.latencyMinutes)
            if let napMed = Statistics.median(lateOnset), let restMed = Statistics.median(rest), napMed - restMed >= 12 {
                out.append(Finding(
                    sentence: "Longer evening naps have typically sat alongside later sleep onset for you. That is an association, not a cause.",
                    sampleCount: longEvening.count,
                    confidence: .low
                ))
            }
        }

        if out.isEmpty {
            out.append(Finding(
                sentence: "Logged naps so far do not show a stable association with bedtime or latency. Zoon will keep watching.",
                sampleCount: naps.count,
                confidence: .low
            ))
        }
        return out
    }
}
