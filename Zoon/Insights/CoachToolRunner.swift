import Foundation

/// Executes a `CoachToolCatalog.Call` against the real engines.
///
/// The catalogue has always known which utterances map to which tools and
/// which of those need confirming. Nothing consulted it: `CoachChat` went
/// straight to the language model, so the catalogue decided nothing and no
/// utterance ever reached a tool. This is the half that was missing.
///
/// Every figure here is read from a computed context or a store. The model is
/// never asked for one and never shown one to reword — "what is my recovery"
/// is answered by `RecoveryScore`, not by prose about it. That is the whole
/// reason tools run before the model rather than after.
@MainActor
struct CoachToolRunner {

    let coordinator: SleepDataCoordinator
    let preferences: UserPreferences
    let naps: NapStore

    /// - Returns: what to say, or `nil` when the tool has nothing to report.
    ///   `nil` is a real answer — Recovery before a night has been scored, a
    ///   Tomorrow plan that needs a sleep need first — and the caller says so
    ///   plainly rather than falling through to the model, which is the one
    ///   path by which a figure could be invented.
    func run(_ call: CoachToolCatalog.Call) -> String? {
        switch call.kind {
        case .getSleepScore: sleepScore()
        case .getRecovery: recovery()
        case .getShortfall: shortfall()
        case .getEnergy: energy()
        case .getMovement: movement()
        case .getTonight: tonight()
        case .getTomorrow: tomorrow()
        case .logCaffeine: logCaffeine(minutes: call.proposedMinutes)
        case .startNap: startNap(minutes: call.proposedMinutes)
        case .prepareTomorrow: prepareTomorrow(minutes: call.proposedMinutes)
        case .setAlarm: setAlarm()
        }
    }

    private var context: DayContext? { coordinator.state.context }

    // MARK: - Reads

    private func sleepScore() -> String? {
        guard let context else { return nil }
        let score = context.sleepIntelligence
        return "Last night's Sleep Intelligence was \(score.percent) — \(score.band.label.lowercased()). \(score.confidence.label)."
    }

    private func recovery() -> String? {
        guard let context else { return nil }
        let recovery = context.recovery
        // The band, not a relabelling as readiness. Morning Recovery is a
        // measurement of the night that has happened; it is not a live
        // daytime state and this sentence must not imply it is.
        return "This morning's Recovery was \(recovery.percent) out of 100, \(recovery.band.label.lowercased()). \(recovery.confidence.label). It describes the night you had, not how you are right now."
    }

    /// §27's second consumer. Movement had exactly one surface -- a card on
    /// Today -- against the seven places the brief names it should reach.
    ///
    /// Reads the snapshot and adds nothing: the sentence, the other measures
    /// where they exist, and no inference about what the movement *means* for
    /// sleep. The brief's line about steps never entering a score applies
    /// here most of all, because a chat answer is exactly where a number would
    /// quietly become a verdict.
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
        guard let plan = tomorrowPlan() else { return nil }
        return "Tonight's sleep window is \(clock(plan.sleepWindowStart))–\(clock(plan.sleepWindowEnd)), for a wake at \(clock(plan.wake))."
    }

    private func tomorrow() -> String? {
        guard let plan = tomorrowPlan() else { return nil }
        return plan.sentence
    }

    private func tomorrowPlan() -> ZoonTomorrow.Plan? {
        ZoonTomorrow.plan(
            event: preferences.commitment().event,
            nights: coordinator.recentNights,
            planning: context.map {
                $0.sleepNeed.planningInputs(
                    outstandingShortfallMinutes: $0.night.sleepDebtMinutes ?? 0
                )
            } ?? SleepPlanningInputs(baselineNeedMinutes: preferences.sleepGoalMinutes),
            napMinutesToday: naps.minutes(on: .now),
            readyBufferMinutes: preferences.morningReadyBufferMinutes
        )
    }

    // MARK: - Writes

    /// Logged against today, which is the day whose behaviours affect the
    /// night that follows — the same rule the Journal screen applies (see
    /// `JournalEntry.date`).
    ///
    /// Late caffeine is a different behaviour from caffeine, not a stronger
    /// version of it, so the hour decides which one is recorded rather than
    /// both being written.
    private func logCaffeine(minutes: Int?) -> String? {
        let isLate = minutes.map { $0 >= CoachToolCatalog.lateCaffeineHour * 60 } ?? false
        let tag: BehaviorTag = isLate ? .caffeineLate : .caffeine
        let day = Date.now
        let night = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        coordinator.setBehavior(.yes, for: tag, on: night, nightKey: nil)
        let when = minutes.map { " at about \(CoachToolCatalog.clock(minutes: $0))" } ?? ""
        return "Logged \(tag.label.lowercased())\(when). You can change it in the Journal."
    }

    private func startNap(minutes: Int?) -> String? {
        let target = minutes ?? 25
        naps.start(targetMinutes: target)
        return "Started a \(target)-minute nap."
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

    /// Turns the wake alarm on rather than scheduling one directly.
    ///
    /// `wakeAlarmEnabled` defaults off on purpose — see its doc comment: an
    /// app that starts making noise because someone updated it is the wrong
    /// outcome. Flipping it from a confirmed sentence is the person asking
    /// for exactly that, and the reply says what will now happen rather than
    /// leaving them to find out at the time.
    private func setAlarm() -> String? {
        guard let plan = tomorrowPlan() else {
            return "There is no wake time to set an alarm from yet."
        }
        preferences.wakeAlarmEnabled = true
        return "Wake alarm on, for \(clock(plan.wake)). You can turn it off in Settings."
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
