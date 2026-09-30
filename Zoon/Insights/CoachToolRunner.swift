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
        case .getHRV: hrv()
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
        case .getForYourAge: await forYourAge()
        case .getNapAdvice: napAdvice()
        case .getSnoring: snoring()
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

    /// Duration, efficiency and wakes, then the stages and the night against
    /// the usual one when there is enough to say it. The chat's own chips --
    /// "How much deep sleep did I get?", "Why do I wake up at night?", "How
    /// did last night compare with my usual?" -- route here, and each of
    /// them used to get the same three numbers, none of which answered it.
    private func lastNightSummary() -> String? {
        guard let context else { return nil }
        let night = context.night
        let format = SleepNightFeatures.formatMinutes
        var parts = ["Last night you were asleep \(format(night.timeAsleepMinutes)), at \(Int(night.sleepEfficiencyPercent.rounded()))% efficiency, with \(night.wakeCount) wake\(night.wakeCount == 1 ? "" : "s")."]
        if night.deepMinutes + night.remMinutes > 0 {
            parts.append("Deep sleep \(format(night.deepMinutes)), REM \(format(night.remMinutes)).")
        }
        let prior = Array(coordinator.recentNights
            .filter { $0.date < night.date }
            .sorted { $0.date < $1.date }
            .suffix(14).map(\.timeAsleepMinutes))
        if prior.count >= 5, let usual = Statistics.median(prior) {
            let gap = night.timeAsleepMinutes - usual
            let span = "your usual \(format(usual)) across the previous \(prior.count) nights"
            parts.append(abs(gap) < 10
                ? "That's about \(span)."
                : "That's \(format(abs(gap))) \(gap > 0 ? "more" : "less") than \(span).")
        }
        parts.append("That's the recorded night — not a medical claim.")
        return parts.joined(separator: " ")
    }

    private func sleepDuration() -> String? {
        guard let context else { return nil }
        return "You were asleep \(SleepNightFeatures.formatMinutes(context.night.timeAsleepMinutes)) last night."
    }

    /// Recovery only when the rest of the app would state it: through the
    /// same presentation gate Today and the watch use. The Coach used to
    /// state the raw number for nights Today shows as "Limited" -- a figure
    /// that, with no HRV or resting heart rate, is really sleep duration.
    private func recovery() -> String? {
        guard let context else { return nil }
        let recovery = context.recovery
        switch recovery.presentation {
        case .available(let score, _):
            return "This morning's Recovery was \(score) out of 100, \(recovery.band.label.lowercased()). \(recovery.confidence.label). It describes the night you had, not how you are right now."
        case .limited(let reason):
            return "Zoon isn't stating a Recovery number for last night. \(reason)"
        case .buildingBaseline(let nights, let required):
            return "Recovery compares a night with your own recent nights, and needs \(required) of them; Zoon has \(nights) so far."
        case .unavailable:
            return "There's no Recovery for last night."
        }
    }

    /// Recovery as a clause for the combined answers, gated the same way.
    private func recoveryClause(_ recovery: RecoveryScore) -> String {
        switch recovery.presentation {
        case .available(let score, _): "Morning Recovery \(score) (\(recovery.band.label.lowercased()))"
        case .limited: "Morning Recovery not stated (too little overnight data)"
        case .buildingBaseline: "Morning Recovery not stated yet (still learning your baseline)"
        case .unavailable: "Morning Recovery not available"
        }
    }

    /// Last night's overnight HRV against the person's own recent average --
    /// the question the Coach tab itself suggests. It used to be answered
    /// with sleep duration and efficiency.
    private func hrv() -> String? {
        guard let night = context?.night else { return nil }
        guard let hrv = night.avgHRV else {
            return "HRV wasn't recorded for last night, so there's nothing to compare. It comes from an Apple Watch worn overnight."
        }
        guard let baseline = night.hrv7DayAvg, baseline > 0 else {
            return "Overnight HRV was \(Int(hrv.rounded())) ms. There isn't a personal average to compare it with yet; that takes about a week of nights."
        }
        let change = (hrv - baseline) / baseline
        let direction = change < -0.08 ? "lower than" : change > 0.08 ? "higher than" : "close to"
        return "Overnight HRV was \(Int(hrv.rounded())) ms, \(direction) your recent \(Int(baseline.rounded())) ms average. It shifts with sleep, alcohol, late exercise, illness and stress, so one night on its own says little. It's a recovery signal, not a medical measure."
    }

    private func movement() -> String? {
        guard let snapshot = coordinator.todayMovement else { return nil }
        var parts = [snapshot.sentence]
        if let detail = snapshot.detail { parts.append(detail + ".") }
        return parts.joined(separator: " ")
    }

    /// The shortfall Today's hero shows: through last night, less today's
    /// naps. `night.sleepDebtMinutes` is the shortfall *entering* last night,
    /// so the Coach answered "1h 35m" beside a Today screen saying "1h 57m".
    /// The figure Today shows. Naps lower tonight's target, not this.
    private var shortfallNow: Double? {
        guard let context, let now = context.shortfallNowMinutes else { return nil }
        return max(0, now)
    }

    private func shortfall() -> String? {
        guard context != nil else { return nil }
        guard let debt = shortfallNow else {
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

    /// The resolved episode every other surface shows -- Tonight, the
    /// widget, the watch, reminders and the alarm. The autopilot's own
    /// bedtime and bed + target ignored a plan the person set, so with a
    /// 22:30-06:00 weekday plan the Coach said 11:10 PM and 7:25 AM.
    private func tonight() -> String? {
        guard let episode = coordinator.tonightEpisode() else { return nil }
        let target = SleepNightFeatures.formatMinutes(episode.targetSleepMinutes)
        var text: String
        if episode.source == .manualPlan, let name = episode.planName {
            text = "Tonight follows your \(name) plan: in bed around \(clock(episode.bed)) for a wake at \(clock(episode.wake)), against a \(target) target."
        } else {
            text = "Tonight's plan is to be in bed around \(clock(episode.bed)) for a wake at \(clock(episode.wake)), targeting \(target)."
        }
        if !episode.isFeasible {
            text += " That window leaves \(SleepNightFeatures.formatMinutes(episode.shortfallMinutes)) short of the target for another night."
        }
        return text
    }

    private func tomorrow() -> String? {
        guard let plan = tomorrowPlan() else { return nil }
        return plan.sentence
    }

    private func fatigueContext() -> String? {
        guard let context else { return nil }
        let night = context.night
        let debt = shortfallNow.map { SleepNightFeatures.formatMinutes($0) } ?? "unknown"
        var parts = [
            "Zoon can't know exactly why you feel tired.",
            "Signals that may be relevant: last night you were asleep \(SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)); \(recoveryClause(context.recovery)); Energy now \(context.bodyBattery.current); Load \(String(format: "%.1f", context.strain.value)); shortfall \(debt)."
        ]
        if let stress = coordinator.todayStress {
            parts.append("Physiological load is \(stress.percent) (\(stress.band.label.lowercased())).")
        }
        parts.append("Use how you feel as the last check — this is not a medical claim.")
        return parts.joined(separator: " ")
    }

    private func trainingContext() -> String? {
        guard let context else { return nil }
        let recovery = context.recovery
        let energy = context.bodyBattery
        let load = context.strain.value
        var text = "\(recoveryClause(recovery)), Energy is \(energy.current), and today's Load is \(String(format: "%.1f", load))."
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

    /// The age range and the heart context, in sentences, from the same
    /// engines the Sleep Need screen and the "For your age" card use -- so
    /// the Coach answers "how much sleep do I need at my age?" on every
    /// iPhone, not only where Apple Intelligence can phrase it.
    private func forYourAge() async -> String? {
        guard let profile = coordinator.demographic else {
            return "Add your age in Settings, under You, or fill it from Health, and I can tell you how much sleep is recommended at your age and how your heart numbers compare."
        }
        var parts: [String] = []
        if let guideline = SleepNeedGuideline.forAge(profile.ageYears) {
            parts.append(guideline.sentence)
            parts.append(guideline.goalSentence(goalMinutes: preferences.sleepGoalMinutes))
        }
        if let learned = context?.learnedSleepNeed.learnedMinutes {
            parts.append("From your own best-rested nights, your need looks like about \(SleepNightFeatures.formatMinutes(learned)).")
        }
        let recent = coordinator.recentNights.suffix(14)
        let resting = recent.compactMap(\.restingHeartRate)
        if resting.count >= 3, let median = Statistics.median(resting) {
            parts.append("Resting heart rate: " + HeartContext.restingHeartRate(median, sex: profile.sex).sentence)
        }
        let hrv = recent.compactMap(\.avgHRV)
        if hrv.count >= 3, let median = Statistics.median(hrv) {
            parts.append("HRV: " + HeartContext.heartRateVariability(median, age: profile.ageYears).sentence)
        }
        if let vo2 = await coordinator.latestVO2Max(),
           let reading = HeartContext.cardioFitness(vo2, age: profile.ageYears, sex: profile.sex) {
            parts.append("Cardio fitness: " + reading.sentence)
        }
        parts.append("These are population figures; your own trend matters more.")
        return parts.joined(separator: " ")
    }

    /// Last night's Snore Check, the recent average, and the logged
    /// behaviour that goes with the biggest change in snoring, if any.
    private func snoring() -> String? {
        let nights = SnoreStore().nights
        guard let last = nights.last else {
            return "There are no Snore Check nights yet. Start it from the Sleep tab at bedtime, leave the phone on the nightstand, and the morning shows when you snored and how loud."
        }
        var parts: [String] = []
        let report = last.report
        let day = last.date.formatted(.dateTime.weekday(.wide))
        if last.snoreMinutes >= 1 {
            var sentence = "On \(day) night Snore Check flagged \(SnoreResultSummary.duration(last.snoreMinutes)) of snoring, \(report.sharePercent)% of the \(SnoreResultSummary.duration(last.monitoredMinutes)) it listened"
            if report.episodeCount > 0 {
                sentence += ", in \(report.episodeCount) episode\(report.episodeCount == 1 ? "" : "s")"
                if let loudest = report.loudest { sentence += ", the loudest \(loudest.label.lowercased())" }
            }
            parts.append(sentence + ".")
        } else {
            parts.append("On \(day) night Snore Check flagged no snoring in the \(SnoreResultSummary.duration(last.monitoredMinutes)) it listened.")
        }
        let recent = nights.suffix(14).filter { $0.monitoredMinutes >= 60 }
        if recent.count >= 3 {
            let average = recent.reduce(0) { $0 + $1.snoreMinutes } / Double(recent.count)
            parts.append("Across your last \(recent.count) nights it averaged \(SnoreResultSummary.duration(average)) a night.")
        }
        if let link = snoreHabitLinks(nights: nights).first, let tag = BehaviorTag(rawValue: link.tag) {
            parts.append("On the \(link.withNights) nights you logged \(tag.label.lowercased()), you snored \(Int(link.withPercent.rounded()))% of the time monitored, against \(Int(link.withoutPercent.rounded()))% on \(link.withoutNights) nights without it. That is a pattern in your own nights, not proof of a cause.")
        }
        parts.append("Snoring on its own is not a medical finding; if it comes with gasping or daytime sleepiness, that is worth raising with a doctor.")
        return parts.joined(separator: " ")
    }

    private func snoreHabitLinks(nights: [SnoreStore.NightSummary]) -> [SnoreHabitLink.Link] {
        let calendar = Calendar.current
        var tagsByDay: [Date: Set<String>] = [:]
        for entry in coordinator.journal.allEntries() {
            tagsByDay[calendar.startOfDay(for: entry.date)] = Set(entry.tagIdentifiers)
        }
        let snoreNights = nights
            .filter { $0.monitoredMinutes >= 60 }
            .map { SnoreHabitLink.Night(day: calendar.startOfDay(for: $0.date), snorePercent: Double($0.snorePercent)) }
        return SnoreHabitLink.links(nights: snoreNights, tagsByDay: tagsByDay)
    }

    private func physiologicalLoad() -> String? {
        guard let stress = coordinator.todayStress else {
            return "Physiological load is not available yet today. It needs daytime heart-rate and HRV samples."
        }
        return "Physiological load so far today is \(stress.percent) out of 100, \(stress.band.label.lowercased()). \(stress.band.detail) This is a daytime autonomic read, not Morning Recovery."
    }

    /// This week against last: the latest seven recorded nights against the
    /// seven before them. It used to be the fourteen-night comparison, so
    /// "What changed this week?" was answered about a month.
    private func trendSummary() -> String? {
        Self.comparison(coordinator.recentNights, window: 7, minimumEach: 4, span: "week")
    }

    private func monthlyChange() -> String? {
        Self.comparison(coordinator.recentNights, window: 14, minimumEach: 7, span: "fortnight")
    }

    /// Recorded sleep over the latest `window` nights against the `window`
    /// before them.
    ///
    /// Refuses rather than compare against too few nights: fourteen nights
    /// set against a single earlier one used to be reported as a change,
    /// worded "the 1 nights before that".
    private static func comparison(_ nights: [SleepNightFeatures], window: Int, minimumEach: Int, span: String) -> String {
        let sorted = nights.sorted { $0.date < $1.date }
        let recent = sorted.suffix(window)
        let earlier = sorted.dropLast(recent.count).suffix(window)
        guard recent.count >= minimumEach, earlier.count >= minimumEach else {
            return "There aren't enough recorded nights yet to compare. Zoon needs at least \(minimumEach) nights in each \(span) it compares; it has \(recent.count) recent and \(earlier.count) before that."
        }
        let recentSleep = recent.map(\.timeAsleepMinutes).reduce(0, +) / Double(recent.count)
        let earlierSleep = earlier.map(\.timeAsleepMinutes).reduce(0, +) / Double(earlier.count)
        let delta = recentSleep - earlierSleep
        let direction: String
        if abs(delta) < 10 {
            direction = "about the same as"
        } else if delta > 0 {
            direction = "about \(SleepNightFeatures.formatMinutes(delta)) more than"
        } else {
            direction = "about \(SleepNightFeatures.formatMinutes(-delta)) less than"
        }
        return "Over your last \(recent.count) recorded nights you slept \(SleepNightFeatures.formatMinutes(recentSleep)) on average, \(direction) the \(earlier.count) nights before that. That compares recorded sleep; it doesn't say what caused any difference."
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
            return "From \(nights.count) nights: \(first.sentence) This is an observation about your recent range, not a medical claim."
        }
        return "Zoon has \(nights.count) nights of history. Nothing has crossed the bar for a personal pattern yet — that is a real answer, not a missing one."
    }

    private func weeklyPlan() -> String? {
        guard context != nil else { return nil }
        let debt = shortfallNow ?? 0
        if debt < 20 {
            return "There is no meaningful shortfall to catch up this week. Keep tonight's window: \(tonight() ?? "open Tonight for the current plan.")."
        }
        let perNight = min(SleepAutopilot.maximumNightlyShift, debt / 3)
        return "Your shortfall is \(SleepNightFeatures.formatMinutes(debt)). Catch-up is spread across nights rather than dumped into one. A typical night might move bedtime earlier by about \(Int(perNight.rounded())) minutes, bounded by the nightly shift cap. Open Tonight for the current window — this is a plan, not a prescription."
    }

    private func currentPriority() -> String? {
        guard let context else { return nil }
        // The resolved episode's bed, as Today uses: it honours a plan the
        // person set, which the plan's own bedtime does not.
        let bed = coordinator.tonightEpisode()?.bed ?? context.tonight.bedtime()
        let nap = NapCoach.recommend(
            now: .now,
            // What Today's nap card is handed, so the two cannot disagree.
            debtMinutes: context.tonightPlanning.currentShortfallMinutes,
            plannedBedtime: bed,
            napMinutesToday: naps.minutes(on: .now),
            lastWake: context.night.wakeTime
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

    /// The nap card's own advice, from the inputs Today hands it, so the
    /// chat and the card cannot disagree.
    private func napAdvice() -> String? {
        guard let context else { return nil }
        let advice = NapCoach.recommend(
            now: .now,
            debtMinutes: context.tonightPlanning.currentShortfallMinutes,
            plannedBedtime: coordinator.tonightEpisode()?.bed ?? context.tonight.bedtime(),
            napMinutesToday: naps.minutes(on: .now),
            lastWake: context.night.wakeTime
        )
        let verdict: String
        switch advice.advice {
        case .recommended(let minutes): verdict = "A nap of about \(minutes) minutes fits today."
        case .optional: verdict = "A nap is optional right now."
        case .avoid: verdict = "Better to skip a nap right now."
        }
        return "\(verdict) \(advice.reason)"
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
        // The wake the scheduler arms, so the alarm it reconciles is this one.
        guard let wake = coordinator.upcomingAlarmWakes().first else {
            return "There is no wake time to set an alarm from yet."
        }
        let alarm = WakeAlarm()
        // Asked here, as the Settings switch asks: scheduling without it
        // fails, and the switch was being turned on regardless.
        guard await alarm.requestAuthorization() else {
            return "Could not set an alarm for \(clock(wake)). \(alarm.unavailabilityReason ?? "Allow alarms for Zoon in iOS Settings, then ask again.")"
        }
        let scheduled = await alarm.schedule(at: wake)
        guard scheduled else {
            return "Could not schedule a real alarm for \(clock(wake)). \(alarm.unavailabilityReason ?? "Check alarm permission in Settings.")"
        }
        // On after it is set, so the scheduler keeps it and re-arms it for
        // the next wake rather than finding a switch it did not expect.
        preferences.wakeAlarmEnabled = true
        return "Wake alarm set for \(clock(wake)). It rings through Silent mode, and Zoon moves it with your plan each time you open the app."
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
