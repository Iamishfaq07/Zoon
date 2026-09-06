import Foundation

/// Frozen inputs for a conversation. Historical questions never borrow today's
/// vitals or future nights, even if a background refresh completes mid-chat.
struct CoachEvidence: Sendable {
    let night: SleepNightFeatures
    let history: [SleepNightFeatures]

    init(night: SleepNightFeatures, history: [SleepNightFeatures]) {
        self.night = night
        self.history = history.filter { $0.date < night.date }.sorted { $0.date < $1.date }
    }

    var vitals: VitalsStatus {
        VitalsStatus.evaluate(features: night, history: history.suffix(30).map {
            VitalsSample(date: $0.date, restingHeartRate: $0.restingHeartRate,
                hrv: $0.avgHRV, respiratoryRate: $0.avgRespiratoryRate,
                oxygenSaturation: $0.avgSpO2, wristTemperatureDelta: $0.wristTempDeltaC,
                sleepMinutes: $0.timeAsleepMinutes, breathingDisturbances: $0.breathingDisturbances)
        })
    }

    var catalog: [String: String] {
        var values = ["sleep": "Sleep: \(Int(night.timeAsleepMinutes)) minutes",
                      "timing": "Bedtime \(night.bedtime.formatted(date: .abbreviated, time: .shortened)); wake \(night.wakeTime.formatted(date: .abbreviated, time: .shortened))"]
        if let hrv = night.avgHRV { values["hrv"] = "HRV: \(Int(hrv.rounded())) ms" }
        if let hr = night.restingHeartRate { values["heart"] = "Resting heart rate: \(Int(hr.rounded())) bpm" }
        return values
    }

    var promptCatalog: String {
        catalog.keys.sorted().map { "\($0): \(catalog[$0]!)" }.joined(separator: "\n")
    }

    func answer(to question: String) -> (text: String, evidence: String?) {
        let q = question.lowercased()
        let id = q.contains("hrv") || q.contains("recovery signal") ? "hrv"
            : q.contains("heart") ? "heart"
            : q.contains("bed") || q.contains("tonight") || q.contains("time") ? "timing" : "sleep"
        guard let fact = catalog[id] else {
            return ("That signal wasn't recorded for this night. Check Body Signals for coverage and source details.", nil)
        }
        let explanation = id == "sleep" ? "This is the recorded sleep duration. One night alone cannot explain why you feel a certain way."
            : id == "timing" ? "These are this night's recorded boundaries. Use Tonight to choose your next bedtime."
            : "Compare this reading with the dated personal range below. A single change does not establish a cause."
        return (explanation, fact)
    }

    /// Generated prose may explain; numbers and citations come from code.
    static func allowsGeneratedProse(_ text: String) -> Bool {
        !text.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }
}
