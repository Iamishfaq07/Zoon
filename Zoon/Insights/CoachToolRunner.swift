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
        case .logCaffeine: logCaffeine(minutes: call.proposedMinutes)
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
        return "Zoon can't know exactly why you feel tired. Signals that may be relevant: last night you were asleep \(SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)); Morning Recovery \(context.recovery.percent); Energy now \(context.bodyBattery.current); Load \(String(format: "%.1f", context.strain.value)); shortfall \(debt). Use how you feel as the last check — this is not a diagnosis."
    }

    private func trainingContext() -> String? {
        guard let context else { return nil }
        let recovery = context.recovery
        let energy = context.bodyBattery
        let load = context.strain.value
        return "Morning Recovery was \(recovery.percent) (\(recovery.band.label.lowercased())), Energy is \(energy.current), and today's Load is \(String(format: "%.1f", load)). If you're deciding between hard and easy training, consider those together with how you feel. This is not medical exercise clearance."
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

    private func logCaffeine(minutes: Int?) -> String? {
        let isLate = minutes.map { $0 >= CoachToolCatalog.lateCaffeineHour * 60 } ?? false
        let tag: BehaviorTag = isLate ? .caffeineLate : .caffeine
        let day = Date.now
        let night = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        var detail: BehaviorDetail?
        if let minutes {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            if let eventTime = Calendar.current.date(from: comps) {
                detail = BehaviorDetail(eventTime: eventTime)
            }
        }
        coordinator.setBehavior(.yes, for: tag.behaviorID, on: night, nightKey: nil, detail: detail)
        let when = minutes.map { " at about \(CoachToolCatalog.clock(minutes: $0))" } ?? ""
        return "Logged \(tag.label.lowercased())\(when). You can change it in the Journal."
    }

    private func startNap(minutes: Int?) async -> String? {
        let target = minutes ?? 25
        naps.start(targetMinutes: target)
        let armed = await naps.armWake()
        if armed {
            return "Started a \(target)-minute nap. Wake is armed."
        }
        return "Started a \(target)-minute nap. A wake could not be scheduled — Focus may silence a notification. Check Settings."
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
