import Foundation

// Split out of SleepDataCoordinator.swift (audit §11), unchanged: what Coach
// is told about standing patterns, and the weekly report built from the same
// history. Read-only over the coordinator's state.

extension SleepDataCoordinator {

    // MARK: - Coach longitudinal context

    /// Compact JSON summary of standing patterns -- this week vs last, the
    /// current regularity/sleep-need read, whatever Cause Finder has
    /// actually found, and what the evidence engines know -- fed to
    /// `CoachChat` alongside tonight's own numbers.
    ///
    /// The evidence half was added after those engines shipped, because the
    /// app had reached a state where it could answer "what changed lately?"
    /// and "what should I test next?" on a screen but not in conversation:
    /// Coach was still reading a digest written before any of them existed.
    /// A question the app can answer in one place and not the other is a
    /// worse failure than one it cannot answer at all -- the person has
    /// already seen that Zoon knows.
    ///
    /// Before this, Coach's only input was `SleepNightFeatures.summaryForLLM`
    /// for the one night on screen: it could describe *tonight* but had no
    /// way to say "your recovery has been climbing all week" or "you tested
    /// worse after late caffeine" -- both already computed elsewhere in the
    /// app (`weeklyReport()`, `JournalCorrelator`) and simply never handed to
    /// the model. This closes that gap the same way `summaryForLLM` closes it
    /// for one night: a flat, terse, `nil`-omitting JSON payload, not a
    /// per-turn tool call -- `FoundationModels.Tool` would let the model ask
    /// for exactly what a given question needs rather than reading a fixed
    /// digest on every turn, but its exact protocol shape couldn't be
    /// verified against Apple's actual SDK in this environment, and 14 wrong
    /// tool conformances is a worse failure mode than an eagerly-built digest
    /// that's merely more context than any single question needs. Live
    /// tool-calling is a clearly scoped follow-up, not implemented here.
    func coachContextDigest() -> String {
        let findings = JournalCorrelator().topFindingPerTag(from: journalObservations(), catalog: behaviorCatalog)
            .sorted { abs($0.percentChange) > abs($1.percentChange) }
            .prefix(5)

        let report = weeklyReport()
        let context = state.context

        let payload = CoachContextDigest(
            nightsLogged: recentNights.count,
            weekAvgRecoveryPct: report?.averageRecovery?.rounded(to: 0),
            weekAvgSleepPerformancePct: report?.averageSleepPerformance?.rounded(to: 0),
            weekAvgHrvMs: report?.averageHRV?.rounded(to: 0),
            weekAvgRestingHeartRate: report?.averageRestingHR?.rounded(to: 0),
            recoveryTrendPct: report?.recoveryTrend?.rounded(to: 0),
            sleepTrendPct: report?.sleepTrend?.rounded(to: 0),
            hrvTrendPct: report?.hrvTrend?.rounded(to: 0),
            goalHitNightsThisWeek: report?.goalHitCount,
            currentRegularityIndex: context?.regularity.index.rounded(to: 0),
            currentRegularityBand: context?.regularity.hasEnoughData == true ? context?.regularity.band.label : nil,
            learnedSleepNeedMinutes: context?.learnedSleepNeed.minutes.rounded(to: 0),
            // The shortfall itself. This was `sleepNeed.debtMinutes`, which is
            // a 33% repayment slice, so the coach quoted a third of the debt
            // as the debt.
            sleepDebtMinutes: context?.shortfallNowMinutes?.rounded(to: 0),
            activeExperimentTag: preferences.activeExperimentTag?.label,
            // Percent-scaled findings only: the digest carries a percentage,
            // and a zero-baseline finding has none to give.
            causeFinderFindings: findings.filter(\.hasRelativeScale).map {
                CoachContextDigest.CorrelatorFinding(
                    behavior: $0.label,
                    metric: $0.metric.shortLabel,
                    percentChange: Int($0.percentChange.rounded()),
                    isImprovement: $0.isImprovement,
                    confidence: $0.confidence.rawValue
                )
            },
            // Capped at three. The digest doc above already worries about
            // handing the model more context than any one question needs,
            // and these engines rank their own output, so the cap costs
            // nothing a fourth entry would have added.
            recentChanges: ChangePointDetector.detectAll(nights: recentNights)
                .prefix(3)
                .map {
                    CoachContextDigest.ChangePoint(
                        metric: $0.metric.label,
                        daysAgo: max(0, Calendar.current.dateComponents(
                            [.day], from: $0.date, to: .now
                        ).day ?? 0),
                        isImprovement: $0.isImprovement
                    )
                },
            testedResults: experiments.outcomes
                .sorted { $0.endDate > $1.endDate }
                .prefix(3)
                .map { outcome -> CoachContextDigest.TestedResult in
                    // The ledger's verdict, not the raw sign of the median
                    // difference: an inconclusive trial has no direction to
                    // hand Coach. See `EvidenceLedger.experimentStatus`.
                    let status = EvidenceLedger.experimentStatus(for: outcome)
                    return CoachContextDigest.TestedResult(
                        behavior: BehaviorTag(rawValue: outcome.tag)?.label ?? outcome.tag,
                        metric: outcome.metricLabel,
                        verdict: status.label,
                        isImprovement: status == .inconclusive ? nil : outcome.isImprovement
                    )
                },
            suggestedNextTest: ExperimentPlanner.next(
                observations: journalObservations(),
                // Built-ins only: the planner proposes guided experiments,
                // and an experiment is always on a behaviour Zoon ships.
                associatedTags: Set(findings.compactMap(\.tag)),
                settledTags: Set(experiments.outcomes.map(\.tag))
            )?.tag.label,
            tonightTarget: context?.tonight.autopilot?.sentence
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Flat DTO mirroring `SleepNightFeatures.LLMPayload` -- `nil` fields
    /// omitted rather than encoded as `null`, so a question the data can't
    /// answer yet doesn't dress up as a measured zero.
    private struct CoachContextDigest: Encodable {
        let nightsLogged: Int
        let weekAvgRecoveryPct: Double?
        let weekAvgSleepPerformancePct: Double?
        let weekAvgHrvMs: Double?
        let weekAvgRestingHeartRate: Double?
        let recoveryTrendPct: Double?
        let sleepTrendPct: Double?
        let hrvTrendPct: Double?
        let goalHitNightsThisWeek: Int?
        let currentRegularityIndex: Double?
        let currentRegularityBand: String?
        let learnedSleepNeedMinutes: Double?
        let sleepDebtMinutes: Double?
        let activeExperimentTag: String?
        let causeFinderFindings: [CorrelatorFinding]
        /// Shifts `ChangePointDetector` located, so "has anything changed
        /// lately?" stops being a question the app can answer on a screen
        /// but not in conversation.
        let recentChanges: [ChangePoint]
        /// Finished experiments -- the only claims in the app that came from
        /// something the person deliberately ran, and the tier Coach should
        /// lean on hardest when they conflict with a mere association.
        let testedResults: [TestedResult]
        /// What `ExperimentPlanner` would suggest testing next. A question,
        /// not a prediction -- the field name says "suggested", and no
        /// direction travels with it, for the same reason the planner
        /// refuses to see one.
        let suggestedNextTest: String?
        /// Tonight's `SleepAutopilot` target, already phrased.
        let tonightTarget: String?

        struct CorrelatorFinding: Encodable {
            let behavior: String
            let metric: String
            let percentChange: Int
            let isImprovement: Bool
            let confidence: String
        }

        struct ChangePoint: Encodable {
            let metric: String
            let daysAgo: Int
            let isImprovement: Bool
        }

        struct TestedResult: Encodable {
            let behavior: String
            let metric: String
            /// `EvidenceLedger.Status.label` -- "Supported", "Not supported"
            /// or "Inconclusive" -- so Coach reads the trial the way the
            /// ledger recorded it.
            let verdict: String
            /// Omitted for an inconclusive trial, which has no direction.
            let isImprovement: Bool?
        }
    }

    /// This week vs last week.
    func weeklyReport() -> WeeklyReport? {
        guard recentNights.count >= 3 else { return nil }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let previousCutoff = calendar.date(byAdding: .day, value: -14, to: .now) ?? .now

        let thisWeek = recentNights.filter { $0.date >= cutoff }
        let lastWeek = recentNights.filter { $0.date >= previousCutoff && $0.date < cutoff }
        guard !thisWeek.isEmpty else { return nil }

        return WeeklyReport.build(
            nights: thisWeek,
            recoveries: recoveryHistory,
            previousNights: lastWeek,
            previousRecoveries: recoveryHistory,
            goalMinutes: preferences.sleepGoalMinutes,
            consistencyMinutes: state.context?.chronotype.consistencyMinutes
        )
    }
}
