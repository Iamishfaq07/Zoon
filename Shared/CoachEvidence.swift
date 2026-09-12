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

    struct Reply: Sendable {
        let text: String
        let evidence: String?
        let action: String?
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
        var values = [
            "sleep": "Sleep: \(Int(night.timeAsleepMinutes.rounded())) minutes",
            "timing": "Bedtime \(night.bedtime.formatted(date: .abbreviated, time: .shortened)); wake \(night.wakeTime.formatted(date: .abbreviated, time: .shortened))"
        ]
        if let hrv = night.avgHRV { values["hrv"] = "HRV: \(Int(hrv.rounded())) ms" }
        if let hr = night.restingHeartRate { values["heart"] = "Resting heart rate: \(Int(hr.rounded())) bpm" }
        if let debt = night.sleepDebtMinutes {
            values["debt"] = "Sleep debt: \(Int(debt.rounded())) minutes"
        }
        return values
    }

    var promptCatalog: String {
        let values = catalog
        return values.keys.sorted().compactMap { key in
            values[key].map { "\(key): \($0)" }
        }.joined(separator: "\n")
    }

    /// Legacy shape used by existing tests and the chat fallback wrapper.
    func answer(to question: String) -> (text: String, evidence: String?) {
        let reply = reply(to: question)
        return (reply.text, reply.evidence)
    }

    /// Local, deterministic reply. Always available — Apple Intelligence is
    /// optional colour on top, not the only way to answer "Am I behind?".
    func reply(to question: String) -> Reply {
        let q = question.lowercased()

        if isGreeting(q) { return greetingReply() }

        if matches(q, ["behind", "debt", "catch up", "enough sleep", "short on sleep", "sleep enough"]) {
            return debtReply()
        }
        if matches(q, ["hrv", "recovery signal", "heart rate variability"]) {
            return hrvReply()
        }
        if matches(q, ["heart", "rhr", "resting"]) && !q.contains("rate variability") {
            return heartReply()
        }
        if matches(q, ["wake", "woke", "awake", "interrupt", "fragment"]) {
            return wakeReply()
        }
        if matches(q, ["train", "workout", "strain", "exercise", "ready"]) {
            return trainReply()
        }
        if matches(q, ["tonight", "bedtime", "prepare", "wind down", "what should i do"]) {
            return tonightReply()
        }
        if matches(q, ["deep", "rem", "stage", "solid", "how did i sleep", "last night"]) {
            return sleepReply()
        }

        // Anything still mentioning the night is close enough to answer with
        // it. Past that, say so.
        if matches(q, ["sleep", "night", "slept", "rest"]) {
            return sleepReply()
        }
        return unknownReply()
    }

    /// Small talk, answered as small talk.
    ///
    /// Checked before the intents so "hi" cannot be swallowed by a substring
    /// match, and kept to whole words so "which" does not read as "hi".
    private func isGreeting(_ q: String) -> Bool {
        let words = Set(
            q.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        guard words.count <= 4 else { return false }
        return !words.isDisjoint(with: [
            "hi", "hey", "hello", "yo", "sup", "hiya", "howdy",
            "thanks", "thank", "ok", "okay", "cool", "nice", "bye"
        ])
    }

    private func greetingReply() -> Reply {
        Reply(
            text: "Hello. Ask me about last night and I'll answer from your own numbers — "
                + "how you slept, your timing, HRV, resting heart rate, how often you woke, "
                + "whether to train today, or what to do tonight.",
            evidence: nil,
            action: nil
        )
    }

    /// What a question outside the data gets.
    ///
    /// This used to be `sleepReply()`. Every unmatched question -- including
    /// "hi" -- returned the identical sleep summary, which is exactly how it
    /// reads on a device where the model is unavailable and every answer
    /// comes from here: the coach appears to give one canned response no
    /// matter what it is asked. Saying what it can answer is both honest and
    /// more useful than answering a question nobody asked.
    private func unknownReply() -> Reply {
        Reply(
            text: "I can only answer from the nights Zoon has recorded. Try asking about how "
                + "you slept, your bedtime and wake timing, HRV, resting heart rate, how often "
                + "you woke, whether to train today, or what to do tonight.",
            evidence: nil,
            action: nil
        )
    }

    /// Generated prose may explain; numbers and citations come from code.
    static func allowsGeneratedProse(_ text: String) -> Bool {
        !text.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }

    // MARK: - Intents

    private func debtReply() -> Reply {
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        let debt = night.sleepDebtMinutes ?? 0
        if debt >= 45 {
            return Reply(
                text: "Yes — you're carrying about \(SleepNightFeatures.formatMinutes(debt)) of unpaid sleep across recent nights. That's a running shortfall, not a verdict on how you will feel today.",
                evidence: catalog["debt"] ?? catalog["sleep"],
                action: "Aim for an earlier wind-down tonight so the next night can repay some of it."
            )
        }
        return Reply(
            text: "No — last night did not add to your sleep debt. You were asleep \(asleep).",
            evidence: catalog["sleep"],
            action: "Keep tonight close to the same window if it felt restful."
        )
    }

    private func hrvReply() -> Reply {
        guard let hrv = night.avgHRV else {
            return Reply(
                text: "HRV wasn't recorded for this night. Check Body Signals for coverage and which device wrote the sample.",
                evidence: nil,
                action: nil
            )
        }
        if let baseline = night.hrv7DayAvg, baseline > 0 {
            let delta = (hrv - baseline) / baseline
            let direction = delta < -0.08 ? "quieter than" : delta > 0.08 ? "higher than" : "close to"
            return Reply(
                text: "Overnight HRV was \(Int(hrv.rounded())) ms, \(direction) your recent \(Int(baseline.rounded())) ms average. That's a recovery signal, not a diagnosis.",
                evidence: catalog["hrv"],
                action: delta < -0.08 ? "A lighter day fits a quieter overnight signal better than a hard session." : nil
            )
        }
        return Reply(
            text: "Overnight HRV was \(Int(hrv.rounded())) ms. There isn't a personal average to compare it with yet.",
            evidence: catalog["hrv"],
            action: nil
        )
    }

    private func heartReply() -> Reply {
        guard let hr = night.restingHeartRate else {
            return Reply(
                text: "Resting heart rate wasn't recorded for this night.",
                evidence: nil,
                action: nil
            )
        }
        return Reply(
            text: "Resting heart rate was \(Int(hr.rounded())) bpm. Compare that with the dated personal range in Body Signals rather than treating one night as a trend.",
            evidence: catalog["heart"],
            action: nil
        )
    }

    private func wakeReply() -> Reply {
        let awake = SleepNightFeatures.formatMinutes(night.awakeMinutes)
        let count = night.wakeCount
        let noun = count == 1 ? "time" : "times"
        return Reply(
            text: "You woke \(count) \(noun) after falling asleep, with \(awake) awake in total. Brief wakes are common; a cluster of them is what the Sleep tab flags as fragmentation.",
            evidence: catalog["sleep"],
            action: count >= 3 ? "A darker, quieter last hour before bed is the usual first change to try." : nil
        )
    }

    private func trainReply() -> Reply {
        let debt = night.sleepDebtMinutes ?? 0
        var lines: [String] = []
        if let hours = night.lastWorkoutHoursBeforeBed, hours < 3 {
            lines.append("Yesterday's session ended about \(Int(hours.rounded()))h before bed, which often sits alongside a shorter night.")
        }
        if debt >= 45 {
            lines.append("You're carrying \(SleepNightFeatures.formatMinutes(debt)) of sleep debt, so a lighter day fits last night better than a hard session.")
            return Reply(
                text: lines.joined(separator: " "),
                evidence: catalog["debt"] ?? catalog["sleep"],
                action: "Keep today's effort easy and protect tonight's bedtime."
            )
        }
        lines.append("Last night doesn't argue against training. Use how you feel this morning as the last check.")
        return Reply(
            text: lines.joined(separator: " "),
            evidence: catalog["sleep"],
            action: nil
        )
    }

    private func tonightReply() -> Reply {
        let bed = night.bedtime.formatted(date: .omitted, time: .shortened)
        let wake = night.wakeTime.formatted(date: .omitted, time: .shortened)
        let debt = night.sleepDebtMinutes ?? 0
        let extra = debt >= 45
            ? " A slightly earlier wind-down would help chip away at the current shortfall."
            : " Repeating a similar window is the simplest plan."
        return Reply(
            text: "Last night you were in bed around \(bed) and up at \(wake).\(extra)",
            evidence: catalog["timing"],
            action: debt >= 45 ? "Open Tonight and pull bedtime a little earlier." : "Open Tonight to lock the same window."
        )
    }

    private func sleepReply() -> Reply {
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        let efficiency = Int(night.sleepEfficiencyPercent.rounded())
        var parts = ["You were asleep \(asleep), at \(efficiency)% efficiency."]
        if night.deepMinutes + night.remMinutes > 0 {
            parts.append("Deep \(SleepNightFeatures.formatMinutes(night.deepMinutes)), REM \(SleepNightFeatures.formatMinutes(night.remMinutes)), \(night.wakeCount) wake\(night.wakeCount == 1 ? "" : "s").")
        }
        parts.append("That's the recorded night — not a diagnosis of why it felt a certain way.")
        return Reply(
            text: parts.joined(separator: " "),
            evidence: catalog["sleep"],
            action: nil
        )
    }

    private func matches(_ question: String, _ keys: [String]) -> Bool {
        keys.contains { question.contains($0) }
    }
}
