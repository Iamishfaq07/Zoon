import Foundation

/// Turns engines that already decided something was warranted into the
/// candidates `OneThing` ranks. Nothing here invents advice; it only
/// translates.
enum OneThingCandidates {

    static func gather(
        tonight: TonightPlan,
        nap: NapCoach.Recommendation,
        recovery: RecoveryScore,
        now: Date,
        caffeineCutoff: Date?
    ) -> [OneThing.Candidate] {
        var candidates: [OneThing.Candidate] = []

        if let autopilot = tonight.autopilot, !autopilot.isHolding, autopilot.shiftMinutes < 0,
           let bed = tonight.bedtime(now: now) {
            let clock = SleepAutopilot.clockLabel(autopilot.targetBedtimeMinutes)
            let hours = bed.timeIntervalSince(now) / 3600
            candidates.append(.init(
                kind: .protectWindow,
                action: "Protect tonight's \(clock) window.",
                reason: autopilot.shortSentence
                    + (tonight.planning.currentShortfallMinutes >= 30
                       ? ". Outstanding shortfall is still \(SleepNightFeatures.formatMinutes(tonight.planning.currentShortfallMinutes))."
                       : "."),
                usefulness: 0.9,
                confidence: autopilot.confidence,
                urgency: urgency(hoursUntil: hours, peakAt: 3, goneBy: 16),
                consequence: min(1, abs(autopilot.shiftMinutes) / SleepAutopilot.maximumNightlyShift)
            ))
        }

        switch nap.advice {
        case .recommended(let minutes):
            candidates.append(.init(
                kind: .takeRecoveryNap,
                action: "A \(minutes)-minute nap now, while bedtime is still far enough away.",
                reason: nap.reason,
                usefulness: 0.75,
                confidence: .moderate,
                urgency: 0.7,
                consequence: 0.55
            ))
        case .avoid:
            if let bed = tonight.bedtime(now: now), bed.timeIntervalSince(now) / 3600 < 8 {
                candidates.append(.init(
                    kind: .skipLateNap,
                    action: "Skip a nap — bedtime is too close.",
                    reason: nap.reason,
                    usefulness: 0.7,
                    confidence: .high,
                    urgency: 0.8,
                    consequence: 0.6
                ))
            }
        case .optional:
            break
        }

        if recovery.presentation.isShowable, recovery.band == .low {
            candidates.append(.init(
                kind: .reduceLoad,
                action: "Keep today's load light.",
                reason: "Morning recovery was low against your own baseline. That is last night's verdict, not a live readiness score.",
                usefulness: 0.8,
                confidence: recovery.confidence,
                urgency: 0.55,
                consequence: 0.7
            ))
        }

        if let cutoff = caffeineCutoff, cutoff > now {
            let hours = cutoff.timeIntervalSince(now) / 3600
            candidates.append(.init(
                kind: .moveCaffeineEarlier,
                action: "Last caffeine by \(cutoff.formatted(.dateTime.hour().minute())).",
                reason: "A general 8-hour guideline before tonight's window, not a personal sensitivity reading.",
                usefulness: 0.55,
                confidence: .low,
                urgency: urgency(hoursUntil: hours, peakAt: 1, goneBy: 10),
                consequence: 0.45
            ))
        }

        return candidates
    }

    /// 1 at `peakAt` hours out, fading to 0 by `goneBy`. Already-passed
    /// windows are not actionable.
    private static func urgency(hoursUntil: Double, peakAt: Double, goneBy: Double) -> Double {
        guard hoursUntil > 0, goneBy > 0 else { return 0 }
        if hoursUntil >= goneBy { return 0.15 }
        let distance = abs(hoursUntil - peakAt)
        return max(0.2, 1 - distance / goneBy)
    }
}
