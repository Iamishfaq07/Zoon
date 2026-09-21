import Foundation

/// Executes a `CoachToolCatalog.Call` against the real engines.
@MainActor
struct CoachToolRunner {

    let coordinator: SleepDataCoordinator
    let preferences: UserPreferences
    let naps: NapStore

    func run(_ call: CoachToolCatalog.Call) async -> String? {
        switch call.kind {
        case .getSleepScore: sleepScore()
        case .getLastNightSummary: lastNightSummary()
        case .getSleepDuration: sleepDuration()
        case .getRecovery: recovery()
        case .getShortfall: shortfall()
        case .getEnergy: energy()
        case .getMovement: movement()
        case .getTonight: tonight()
        case .getTomorrow: tomorrow()
        case .getFatigueContext: fatigueContext()
        case .getTrainingContext: trainingContext()
        case .getTrendSummary: trendSummary()
        case .getMonthlyChange: monthlyChange()
        case .getBehaviorEvidence: behaviorEvidence()
        case .getLearningStatus: learningStatus()
        case .getWeeklyPlan: weeklyPlan()
        case .getCurrentPriority: currentPriority()
        case .getPhysiologicalLoad: physiologicalLoad()
        case .getDailyLoad: dailyLoad()
        case .logCaffeine: logCaffeine(minutes: call.proposedMinutes, servings: call.proposedServings)
        case .startNap: await startNap(minutes: call.proposedMinutes)
        case .prepareTomorrow: prepareTomorrow(minutes: call.proposedMinutes)
        case .setAlarm: await setAlarm()
        }
    }

    private var context: DayContext? { coordinator.state.context }

    private func sleepScore() -> String? {
        guard let context else { return nil }
        let score = context.sleepIntelligence
        return "Last night's Sleep Intelligence was \(score.percent) — \(score.band.label.lowercased()). \(score.confidence.label)."
    }

    private func lastNightSummary() -> String? {
        guard let context else { return nil }
        let night = context.night
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        return "Last night you were asleep \(asleep), at \(Int(night.sleepEfficiencyPercent.rounded()))% efficiency, with \(night.wakeCount) wake\(night.wakeCount == 1 ? "" : "s"). That's the recorded night — not a diagnosis."
    }

    private func sleepDuration() -> String? {
        guard let context else { return nil }
        return "You were asleep \(SleepNightFeatures.formatMinutes(context.night.timeAsleepMinutes)) last night."
    }

    private func recovery() -> String? {
        guard let context else { return nil }
        let recovery = context.recovery
        return "This morning's Recovery was \(recovery.percent) out of 100, \(recovery.band.label.lowercased()). \(recovery.confidence.label). It describes the night you had, not how you are right now."
    }

    private func movement() -> String? {
        guard let snapshot = coordinator.todayMovement else { return nil }
        var parts = [snapshot.sentence]
        if let detail = snapshot.detail { parts.append(detail + ".") }
        return parts.joined(separator: " ")
    }

    private func shortfall() -> String? {
        guard let context else { return nil }
        guard let debt = context.night.sleepDebtMinutes else {
            return "There is not enough history yet to measure a shortfall."
        }
        guard debt >= 1 else { return "You have no outstanding sleep shortfall." }
        return "Your sleep shortfall is \(SleepNightFeatures.formatMinutes(debt))."
    }

    private func energy() -> String? {
        guard let context else { return nil }
        let battery = context.bodyBattery
        let note = battery.isEstimate ? " It is an estimate — \(battery.provenance.label.lowercased())." : ""
        return "Energy now is \(battery.current) out of 100.\(note)"
    }

    private func tonight() -> String? {
        guard let plan = context?.tonight else { return nil }
        guard let bed = plan.bedtime(), let wake = plan.wakeTime() else { return nil }
        return "Tonight's plan is to be in bed around \(clock(bed)) for a wake at \(clock(wake)), targeting \(SleepNightFeatures.formatMinutes(plan.suggestedSleepTargetMinutes))."
    }

    private func tomorrow() -> String? {
        guard let plan = tomorrowPlan() else { return nil }
        return plan.sentence
    }

    private func fatigueContext() -> String? {
        guard let context else { return nil }
        let night = context.night
        let debt = night.sleepDebtMinutes.map { SleepNightFeatures.formatMinutes($0) } ?? "unknown"
        var parts = [
            "Zoon can't know exactly why you feel tired.",
            "Signals that may be relevant: last night you were asleep \(SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)); Morning Recovery \(context.recovery.percent); Energy now \(context.bodyBattery.current); Load \(String(format: "%.1f", context.strain.value)); shortfall \(debt)."
        ]
        if let stress = coordinator.todayStress {
            parts.append("Physiological load is \(stress.percent) (\(stress.band.label.lowercased())).")
        }
        parts.append("Use how you feel as the last check — this is not a diagnosis.")
        return parts.joined(separator: " ")
    }

    private func trainingContext() -> String? {
        guard let context else { return nil }
        let recovery = context.recovery
        let energy = context.bodyBattery
        let load = context.strain.value
        var text = "Morning Recovery was \(recovery.percent) (\(recovery.band.label.lowercased())), Energy is \(energy.current), and today's Load is \(String(format: "%.1f", load))."
        if let stress = coordinator.todayStress {
            text += " Physiological load is \(stress.percent) (\(stress.band.label.lowercased()))."
        }
        text += " If you're deciding between hard and easy training, consider those together with how you feel. This is not medical exercise clearance."
        return text
    }

    private func dailyLoad() -> String? {
        guard let context else { return nil }
        let note = context.strain.isEstimate ? " It is an estimate from the heart-rate coverage available so far." : ""
        return "Today's Load is \(String(format: "%.1f", context.strain.value)) on a 0–21 scale.\(note) Load is cardiovascular work today, not a verdict on how recovered you are."
    }

    private func physiologicalLoad() -> String? {
        guard let stress = coordinator.todayStress else {
            return "Physiological load is not available yet today. It needs daytime heart-rate and HRV samples."
        }
        return "Physiological load so far today is \(stress.percent) out of 100, \(stress.band.label.lowercased()). \(stress.band.detail) This is a daytime autonomic read, not Morning Recovery."
    }

    private func trendSummary() -> String? {
        monthlyChange()
    }

    private func monthlyChange() -> String? {
        let nights = coordinator.recentNights.sorted { $0.date < $1.date }
        guard nights.count >= 8 else {
            return "There are not enough recent nights yet to describe a monthly change. Zoon needs about two weeks on each side of a comparison."
        }
        let recent = nights.suffix(14)
        let earlier = nights.dropLast(recent.count).suffix(14)
        guard !earlier.isEmpty else {
            return "There is a recent stretch of nights, but not an earlier one to compare it with yet."
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
        return "Over the last \(recent.count) nights you were asleep \(SleepNightFeatures.formatMinutes(recentSleep)) on average, \(direction) the \(earlier.count) nights before that. That's a comparison of recorded duration, not a cause."
    }

    private func behaviorEvidence() -> String? {
        let findings = JournalCorrelator().findings(
            from: coordinator.journalObservations(),
            catalog: coordinator.behaviorCatalog
        )
        guard let strongest = findings.first else {
            return "There are not enough tagged nights yet to say whether a habit is associated with how long you sleep. Zoon needs matched pairs, not a guess. Correlation is not causation."
        }
        let samples = strongest.matchedPairCount
        return "\(strongest.plainSentence) Based on \(samples) matched pairs, \(strongest.confidence.label.lowercased()). This is an association in your log, not proof that the habit caused the nights."
    }

    private func learningStatus() -> String? {
        let nights = coordinator.recentNights
        guard nights.count >= 7 else {
            return "Zoon is still collecting nights. Personal patterns stay hidden until there is enough of your own history to compare against."
        }
        let items = PersonalLearning.resilience(nights: nights, disruptionDates: [])
        if let first = items.first {
            return "From \(nights.count) nights: \(first.sentence) This is an observation about your recent range, not a diagnosis."
        }
        return "Zoon has \(nights.count) nights of history. Nothing has crossed the bar for a personal pattern yet — that is a real answer, not a missing one."
    }

    private func weeklyPlan() -> String? {
        guard let context else { return nil }
        let debt = context.night.sleepDebtMinutes ?? 0
        if debt < 20 {
            return "There is no meaningful shortfall to catch up this week. Keep tonight's window: \(tonight() ?? "open Tonight for the current plan.")."
        }
        let perNight = min(SleepAutopilot.maximumNightlyShift, debt / 3)
        return "Your shortfall is \(SleepNightFeatures.formatMinutes(debt)). Catch-up is spread across nights rather than dumped into one. A typical night might move bedtime earlier by about \(Int(perNight.rounded())) minutes, bounded by the nightly shift cap. Open Tonight for the current window — this is a plan, not a prescription."
    }

    private func currentPriority() -> String? {
        guard let context else { return nil }
        let bed = context.tonight.bedtime()
        let nap = NapCoach.recommend(
            now: .now,
            debtMinutes: context.night.sleepDebtMinutes ?? 0,
            plannedBedtime: bed,
            napMinutesToday: naps.minutes(on: .now)
        )
        let candidates = OneThingCandidates.gather(
            tonight: context.tonight,
            nap: nap,
            recovery: context.recovery,
            now: .now,
            caffeineCutoff: bed.flatMap { CaffeineCutoff.time(bedtime: $0) }
        )
        if let selection = OneThing.choose(from: candidates) {
            return "\(selection.candidate.action) \(selection.candidate.reason) That is the one action worth the attention, not a bedtime plan by default."
        }
        return "Nothing is urgent enough to be the one focus right now. Keep tonight's window if you have one, and use how you feel with Recovery, Energy, and Load."
    }

    private func tomorrowPlan() -> ZoonTomorrow.Plan? {
        ZoonTomorrow.plan(
            event: preferences.commitment().event,
            nights: coordinator.recentNights,
            planning: context?.tonight.planning ?? SleepPlanningInputs(baselineNeedMinutes: preferences.sleepGoalMinutes),
            napMinutesToday: naps.minutes(on: .now),
            readyBufferMinutes: preferences.morningReadyBufferMinutes
        )
    }

    private func logCaffeine(minutes: Int?, servings: Int?) -> String? {
        let isLate = minutes.map { $0 >= CoachToolCatalog.lateCaffeineHour * 60 } ?? false
        let tag: BehaviorTag = isLate ? .caffeineLate : .caffeine
        let day = Date.now
        let night = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        var detail: BehaviorDetail?
        var eventTime: Date?
        if let minutes {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            eventTime = Calendar.current.date(from: comps)
        }
        if eventTime != nil || servings != nil {
            detail = BehaviorDetail(
                quantity: servings.map(Double.init),
                unit: servings == nil ? nil : "servings",
                eventTime: eventTime
            )
        }
        coordinator.setBehavior(.yes, for: tag.behaviorID, on: night, nightKey: nil, detail: detail)
        let when = minutes.map { " at about \(CoachToolCatalog.clock(minutes: $0))" } ?? ""
        let amount = servings.map { " (\($0) serving\($0 == 1 ? "" : "s"))" } ?? ""
        return "Logged \(tag.label.lowercased())\(amount)\(when). Milligrams were not assumed. You can change it in the Journal."
    }

    private func startNap(minutes: Int?) async -> String? {
        let target = minutes ?? 25
        let result = await naps.startAndArm(targetMinutes: target)
        return "Started a \(target)-minute nap. \(result.wake.coachSentence)"
    }

    private func prepareTomorrow(minutes: Int?) -> String? {
        guard let minutes else {
            return "Open Tomorrow and set the time you need to be ready for."
        }
        guard let start = ManualCommitment(hour: minutes / 60, minute: minutes % 60).start(now: .now)
        else { return nil }
        preferences.setTomorrowEvent(date: start)
        guard let plan = tomorrowPlan() else {
            return "Set tomorrow's start time to \(CoachToolCatalog.clock(minutes: minutes))."
        }
        return "Set tomorrow's start time to \(CoachToolCatalog.clock(minutes: minutes)). \(plan.sentence)"
    }

    private func setAlarm() async -> String? {
        guard let wake = context?.tonight.wakeTime() ?? tomorrowPlan()?.wake else {
            return "There is no wake time to set an alarm from yet."
        }
        preferences.wakeAlarmEnabled = true
        let alarm = WakeAlarm()
        let scheduled = await alarm.schedule(at: wake)
        if scheduled {
            return "Wake alarm scheduled for \(clock(wake))."
        }
        return "Could not schedule a real alarm for \(clock(wake)). \(alarm.unavailabilityReason ?? "Check alarm permission in Settings.")"
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
