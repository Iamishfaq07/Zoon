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
        if let through = night.shortfallThroughNightMinutes {
            values["debt"] = "Recent shortfall after this night: \(Int(through.rounded())) minutes"
        } else if let before = night.shortfallBeforeNightMinutes {
            values["debt"] = "Recent shortfall entering this night: \(Int(before.rounded())) minutes"
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
        // Before any routing: a question about a condition is answered as
        // one. "Do I have sleep apnea?" contains "sleep", and the keyword
        // fallback used to answer it with last night's duration.
        if Self.isMedicalQuestion(question) {
            return medicalReply()
        }
        switch CoachIntentRouter.classify(question) {
        case .greeting:
            return Reply(text: CoachIntentRouter.greetingReply(), evidence: nil, action: nil)
        case .capabilities:
            return Reply(text: CoachIntentRouter.capabilitiesReply(), evidence: nil, action: nil)
        case .thanks:
            return Reply(text: CoachIntentRouter.thanksReply(), evidence: nil, action: nil)
        case .farewell:
            return Reply(text: CoachIntentRouter.farewellReply(), evidence: nil, action: nil)
        case .cancel:
            return Reply(text: CoachIntentRouter.cancelReply(), evidence: nil, action: nil)
        case .tool(let call):
            // The catalog is the source of truth for *which* question this is.
            // Falling through to the coarser keyword list below is how
            // "When should I sleep?" used to be answered with last night's
            // duration — it contains "sleep", and that branch ran first.
            switch call.kind {
            case .getTonight, .getTomorrow:
                return tonightReply()
            case .getFatigueContext:
                return fatigueReply()
            case .getTrainingContext:
                return trainReply()
            case .getCurrentPriority:
                return priorityReply()
            case .getSleepDuration, .getSleepScore:
                return sleepReply()
            case .getLastNightSummary:
                // Catalog maps HRV and wake questions here too. Do not
                // collapse them into duration copy — the local keyword
                // branches are finer than the catalog kind.
                return lastNightReply(to: question)
            case .getShortfall:
                return debtReply()
            case .getTrendSummary, .getMonthlyChange:
                return trendReply()
            case .getRecovery:
                return recoveryLocalReply()
            case .getEnergy:
                return energyLocalReply()
            case .getDailyLoad, .getPhysiologicalLoad:
                return loadLocalReply()
            case .getMovement:
                return movementLocalReply()
            case .getBehaviorEvidence:
                return behaviorReply()
            case .getLearningStatus:
                return learningReply()
            case .getWeeklyPlan:
                return weeklyReply()
            default:
                break
            }
        case .unknown:
            break
        }

        let q = question.lowercased()

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
        if matches(q, ["train", "workout", "strain", "exercise"]) && !q.contains("energy") {
            return trainReply()
        }
        if matches(q, ["tired", "fatigue", "exhausted", "why am i so sleepy"]) {
            return fatigueReply()
        }
        if matches(q, ["tonight", "bedtime", "prepare", "wind down", "what should i do", "when should i sleep"]) {
            return tonightReply()
        }
        if matches(q, ["deep", "rem", "stage", "solid", "how did i sleep", "last night", "how much did i sleep"]) {
            return sleepReply()
        }

        if matches(q, ["sleep", "slept"]) {
            return sleepReply()
        }
        return unknownReply()
    }

    /// Terms that make a question about a medical condition rather than
    /// about last night's numbers.
    static let medicalQuestionTerms = [
        "apnea", "apnoea", "insomnia", "narcolepsy", "disorder", "diagnos",
        "syndrome", "disease", "medical condition", "restless leg", "is something wrong with me"
    ]

    static func isMedicalQuestion(_ question: String) -> Bool {
        let q = question.lowercased()
        return medicalQuestionTerms.contains { q.contains($0) }
    }

    /// No diagnosis, no reassurance, and a clear route to someone who can
    /// actually answer. Worded to pass `DiagnosticLanguageGuard` itself.
    private func medicalReply() -> Reply {
        Reply(
            text: "Zoon can't tell whether you have a medical condition — a wearable's sleep numbers aren't a clinical test. It can show what was measured, like breathing disturbances Apple recorded or how often you woke. If snoring, pauses in breathing or daytime sleepiness worry you, that's worth raising with a clinician.",
            evidence: nil,
            action: nil
        )
    }

    /// Small talk is handled by `CoachIntentRouter` before this type runs.

    /// What a question outside the data gets.
    private func unknownReply() -> Reply {
        Reply(
            text: CoachIntentRouter.unknownReply(),
            evidence: nil,
            action: nil
        )
    }

    /// Generated prose may explain; numbers and citations come from code.
    static func allowsGeneratedProse(_ text: String) -> Bool {
        !text.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }

    // MARK: - Intents

    /// Below this, a night's own gap is not reported as "adding" to the
    /// shortfall: a quarter hour is inside ordinary night-to-night noise.
    static let addedShortfallThresholdMinutes = 15.0

    /// The running shortfall as of the morning after `night` -- that night's
    /// figure, never today's. Falls back to the figure *entering* the night
    /// only where the night's need was never recorded, and every reply that
    /// uses the fallback avoids claiming anything about the night itself.
    private var runningShortfall: Double {
        night.shortfallThroughNightMinutes ?? night.shortfallBeforeNightMinutes ?? 0
    }

    /// "Am I behind?" and "Did last night add to it?".
    ///
    /// This used to read `sleepDebtMinutes`, the shortfall *entering* the
    /// night, and on a small value answer "last night did not add to your
    /// sleep debt" -- a claim about a night that figure does not include. A
    /// 5h30 night after a clean week was told it added nothing. It now reads
    /// the shortfall through the night and the night's own gap.
    private func debtReply() -> Reply {
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        let total = runningShortfall
        let added = night.shortfallAddedByNightMinutes
        let threshold = Self.addedShortfallThresholdMinutes

        if total >= 45 {
            var text = "Yes — you're carrying about \(SleepNightFeatures.formatMinutes(total)) of shortfall across recent nights"
            if let added, added >= threshold {
                text += ", including about \(SleepNightFeatures.formatMinutes(added)) from this night"
            } else if added != nil {
                text += "; this night itself met or came close to your need"
            }
            text += ". That's a running shortfall, not a verdict on how you will feel today."
            return Reply(
                text: text,
                evidence: catalog["debt"] ?? catalog["sleep"],
                action: "Aim for an earlier wind-down tonight so the next night can repay some of it."
            )
        }
        guard let added else {
            return Reply(
                text: "No — your recent shortfall is small. Zoon doesn't have the need this night was measured against, so it can't say whether the night itself added to it. You were asleep \(asleep).",
                evidence: catalog["debt"] ?? catalog["sleep"],
                action: nil
            )
        }
        if added >= threshold {
            return Reply(
                text: "Not much overall, but this night did add to it: you were asleep \(asleep), about \(SleepNightFeatures.formatMinutes(added)) short of your need. The running shortfall is still small.",
                evidence: catalog["debt"] ?? catalog["sleep"],
                action: "Keep tonight's window protected so it doesn't build."
            )
        }
        return Reply(
            text: "No — this night met your need, so it did not add to your shortfall. You were asleep \(asleep).",
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
                text: "Overnight HRV was \(Int(hrv.rounded())) ms, \(direction) your recent \(Int(baseline.rounded())) ms average. That's a recovery signal, not a medical claim. Consider it alongside Morning Recovery, Energy, and how you feel — one quieter night is not an exercise prescription.",
                evidence: catalog["hrv"],
                action: nil
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

    private func fatigueReply() -> Reply {
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        var text = "Zoon can't know exactly why you feel tired, but a few signals may be relevant. Last night you were asleep \(asleep)."
        if night.shortfallThroughNightMinutes != nil || night.shortfallBeforeNightMinutes != nil {
            text += " Recent shortfall is \(SleepNightFeatures.formatMinutes(runningShortfall))."
        }
        text += " Pair that with Morning Recovery, Energy, and current Load — this is not a medical claim."
        return Reply(text: text, evidence: catalog["sleep"], action: nil)
    }

    private func trainReply() -> Reply {
        let debt = runningShortfall
        var lines: [String] = []
        if let hours = night.lastWorkoutHoursBeforeBed, hours < 3 {
            lines.append("Yesterday's session ended about \(Int(hours.rounded()))h before bed. That is a timing observation, not proof that the workout shortened the night.")
        }
        if debt >= 45 {
            lines.append("Your recent shortfall is elevated (\(SleepNightFeatures.formatMinutes(debt))). Consider it together with how you feel, Morning Recovery, Energy, and current Load.")
            return Reply(
                text: lines.joined(separator: " "),
                evidence: catalog["debt"] ?? catalog["sleep"],
                action: "Open Recovery, Energy, and Load before deciding how hard to go."
            )
        }
        lines.append("Last night's numbers alone are not a training plan. Use how you feel this morning together with Morning Recovery, Energy, and Load.")
        return Reply(
            text: lines.joined(separator: " "),
            evidence: catalog["sleep"],
            action: nil
        )
    }

    private func tonightReply() -> Reply {
        let debt = runningShortfall
        let extra = debt >= 45
            ? " There is an outstanding shortfall of \(SleepNightFeatures.formatMinutes(debt)); Tonight will show how much of that is repaid in this plan."
            : " Tonight's window is computed independently of last night's clocks."
        return Reply(
            text: "Use the Tonight plan for bedtime, wind-down, and wake. Last night is a record, not tonight's prescription.\(extra)",
            evidence: catalog["timing"],
            action: "Open Tonight to see the current window."
        )
    }

    /// "What should I focus on?" is the current priority, not Tonight by default.
    private func priorityReply() -> Reply {
        if runningShortfall >= 45 {
            let debt = runningShortfall
            return Reply(
                text: "Protect tonight's earlier sleep window. Recent shortfall is \(SleepNightFeatures.formatMinutes(debt)). That is the one action last night's record supports — not a live Energy or Load read.",
                evidence: catalog["debt"] ?? catalog["sleep"],
                action: "Open Tonight to see how much of that shortfall this plan can repay."
            )
        }
        if let hours = night.lastWorkoutHoursBeforeBed, hours < 2 {
            return Reply(
                text: "Yesterday's session ended about \(Int(hours.rounded()))h before bed. Keep tonight's window protected rather than adding another late session. This is a timing observation, not an exercise prescription.",
                evidence: catalog["sleep"],
                action: nil
            )
        }
        return Reply(
            text: "Nothing from last night is urgent enough to be the one focus. Use how you feel with Morning Recovery, Energy, and Load, and keep tonight's window if you have one.",
            evidence: catalog["sleep"],
            action: nil
        )
    }

    private func trendReply() -> Reply {
        let prior = history.suffix(28)
        guard prior.count >= 8 else {
            return Reply(
                text: "There are not enough recent nights yet to describe a change. Zoon needs about two weeks before a comparison is worth making.",
                evidence: nil,
                action: nil
            )
        }
        let recent = Array(prior.suffix(14))
        let earlier = Array(prior.dropLast(recent.count).suffix(14))
        guard !earlier.isEmpty else {
            return Reply(
                text: "There is a recent stretch of nights, but not an earlier one to compare it with yet.",
                evidence: catalog["sleep"],
                action: nil
            )
        }
        let recentSleep = recent.map(\.timeAsleepMinutes).reduce(0, +) / Double(recent.count)
        let earlierSleep = earlier.map(\.timeAsleepMinutes).reduce(0, +) / Double(earlier.count)
        let delta = recentSleep - earlierSleep
        let direction: String
        if abs(delta) < 10 {
            direction = "about the same length as"
        } else if delta > 0 {
            direction = "about \(SleepNightFeatures.formatMinutes(delta)) longer than"
        } else {
            direction = "about \(SleepNightFeatures.formatMinutes(-delta)) shorter than"
        }
        return Reply(
            text: "Over the last \(recent.count) nights you were asleep \(SleepNightFeatures.formatMinutes(recentSleep)) on average, \(direction) the \(earlier.count) nights before that. That's a comparison of recorded duration, not a cause.",
            evidence: catalog["sleep"],
            action: nil
        )
    }

    private func sleepReply() -> Reply {
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        let efficiency = Int(night.sleepEfficiencyPercent.rounded())
        var parts = ["You were asleep \(asleep), at \(efficiency)% efficiency."]
        if night.deepMinutes + night.remMinutes > 0 {
            parts.append("Deep \(SleepNightFeatures.formatMinutes(night.deepMinutes)), REM \(SleepNightFeatures.formatMinutes(night.remMinutes)), \(night.wakeCount) wake\(night.wakeCount == 1 ? "" : "s").")
        }
        parts.append("That's the recorded night — not a medical claim about why it felt a certain way.")
        return Reply(
            text: parts.joined(separator: " "),
            evidence: catalog["sleep"],
            action: nil
        )
    }

    /// Catalog `.getLastNightSummary` is coarser than the local branches.
    /// HRV and wake questions must not become a duration summary.
    private func lastNightReply(to question: String) -> Reply {
        let q = question.lowercased()
        if matches(q, ["hrv", "recovery signal", "heart rate variability"]) {
            return hrvReply()
        }
        if matches(q, ["wake", "woke", "awake", "interrupt", "fragment"]) {
            return wakeReply()
        }
        return sleepReply()
    }

    private func recoveryLocalReply() -> Reply {
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        return Reply(
            text: "Morning Recovery is scored on Today from last night's physiology — this local record does not invent that number. You were asleep \(asleep). Recovery describes the night, not live afternoon capacity.",
            evidence: catalog["sleep"],
            action: "Open Today for Morning Recovery."
        )
    }

    private func energyLocalReply() -> Reply {
        return Reply(
            text: "Energy is a live daytime reserve. Last night's record does not stand in for it. Use Today for the current Energy number, together with Load.",
            evidence: nil,
            action: "Open Today for Energy."
        )
    }

    private func loadLocalReply() -> Reply {
        return Reply(
            text: "Load and physiological load are today's cardiovascular and autonomic work. They are not in last night's record and they are not Morning Recovery. Open Today for the live reads.",
            evidence: nil,
            action: "Open Today for Load."
        )
    }

    private func movementLocalReply() -> Reply {
        return Reply(
            text: "Movement is today's steps and activity against your usual day. Last night's sleep record does not include it.",
            evidence: nil,
            action: "Open Today for movement."
        )
    }

    private func behaviorReply() -> Reply {
        var bits: [String] = []
        if let mg = night.lateCaffeineMg, mg > 0 {
            bits.append("late caffeine (\(Int(mg.rounded())) mg) is on last night's record")
        }
        if let drinks = night.alcoholicBeverages, drinks > 0 {
            bits.append("alcohol is on last night's record")
        }
        if bits.isEmpty {
            return Reply(
                text: "There are not enough tagged nights in this local record to describe a habit association. Open Evidence for matched comparisons. Correlation is not causation.",
                evidence: nil,
                action: "Open Evidence."
            )
        }
        return Reply(
            text: "On this night, \(bits.joined(separator: " and ")). That is a logged exposure, not proof it caused the sleep you had.",
            evidence: catalog["sleep"],
            action: nil
        )
    }

    private func learningReply() -> Reply {
        let count = history.count
        if count < 7 {
            return Reply(
                text: "Zoon is still collecting nights (\(count) before this one). Personal patterns stay hidden until there is enough of your own history to compare against.",
                evidence: nil,
                action: nil
            )
        }
        return Reply(
            text: "From \(count) earlier nights plus this one, Zoon can compare duration and timing against your own range. Open Model Health for what is strong versus still growing. This is an observation, not a medical claim.",
            evidence: catalog["sleep"],
            action: "Open Model Health."
        )
    }

    private func weeklyReply() -> Reply {
        let debt = runningShortfall
        if debt < 20 {
            return Reply(
                text: "There is no meaningful shortfall to catch up this week. Keep tonight's window close to usual.",
                evidence: catalog["sleep"],
                action: "Open Tonight for the current window."
            )
        }
        return Reply(
            text: "Your shortfall is \(SleepNightFeatures.formatMinutes(debt)). Catch-up is spread across nights rather than dumped into one. Open Tonight for the current window — this is a plan, not a prescription.",
            evidence: catalog["debt"] ?? catalog["sleep"],
            action: "Open Tonight."
        )
    }

    private func matches(_ question: String, _ keys: [String]) -> Bool {
        keys.contains { question.contains($0) }
    }
}
