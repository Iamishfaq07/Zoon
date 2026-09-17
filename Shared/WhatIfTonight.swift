import Foundation

/// Tonight's window, moved, and what actually follows from moving it.
///
/// Everything here is arithmetic on a clock. Move bedtime an hour later
/// against a fixed alarm and the window loses an hour — that is not a model,
/// it is subtraction, and it is true before the night happens. The caffeine
/// cutoff, the wind-down target and the morning-light window are each a fixed
/// offset from one of the two ends, computed by the engines that already own
/// them.
///
/// **What it deliberately does not do.** It does not say Recovery will be 63.
/// It does not predict a Sleep Score, a mood, or how anyone will feel. Those
/// need a validated model of a night that has not happened, and Zoon does not
/// have one. The distinction is the same one `SleepRunway` draws: a window too
/// short to hold the need is a fact about the clock; what the night does
/// inside that window is not.
///
/// Sleep opportunity is a ceiling. Nobody is asleep for the whole window, and
/// `SleepOpportunity` is the measurement of that gap after the fact.
struct WhatIfTonight: Hashable, Sendable {

    /// The window as it currently stands, for the "instead of" comparison.
    struct Reference: Hashable, Sendable {
        let bedtime: Date
        let wake: Date

        var opportunityMinutes: Double { max(0, wake.timeIntervalSince(bedtime) / 60) }
    }

    let bedtime: Date
    let wake: Date
    /// Tonight's target, repayment included. For display and for the gap.
    let needMinutes: Double
    /// Outstanding shortfall going into tonight.
    let shortfallMinutes: Double
    /// Tonight's need *before* repayment — what the ledger moves against.
    ///
    /// Separate from `needMinutes` for the reason `SleepRunway` documents:
    /// repayment raises what to aim for, it is not a second debt to service.
    /// Advancing the ledger by the repaid target would mean a window that
    /// comfortably covers the need still grew the shortfall, and the debt
    /// could never be paid off.
    let baseNeedMinutes: Double
    let reference: Reference?

    /// The most sleep this window leaves room for.
    var opportunityMinutes: Double { max(0, wake.timeIntervalSince(bedtime) / 60) }

    /// Need minus opportunity. Positive means the window cannot hold it.
    var gapMinutes: Double { needMinutes - opportunityMinutes }

    var isShort: Bool { gapMinutes >= WhatIfTonight.shortTolerance }

    /// Shortfall after tonight, if the whole window were slept.
    ///
    /// The optimistic bound, and labelled as one. A window that cannot even
    /// in principle repay anything is the finding worth surfacing; whether a
    /// window that could actually does is a question about the night.
    var projectedShortfallMinutes: Double {
        max(0, shortfallMinutes + baseNeedMinutes - opportunityMinutes)
    }

    /// Wind-down target: a fixed lead before the window opens.
    var windDown: Date {
        bedtime.addingTimeInterval(-ZoonTomorrow.windDownLeadMinutes * 60)
    }

    /// The general eight-hour guideline, not a personal sensitivity. `nil`
    /// when the cutoff has already passed — see `CaffeineCutoff`.
    func caffeineCutoff(now: Date = .now) -> Date? {
        CaffeineCutoff.time(bedtime: bedtime, now: now)
    }

    /// Morning light within this window of waking is the strongest cue Zoon
    /// can name.
    var morningLightUntil: Date {
        wake.addingTimeInterval(ZoonTomorrow.morningLightMinutes * 60)
    }

    /// What a nap would mean for this window.
    func napAdvice(now: Date = .now, napMinutesToday: Double = 0) -> NapCoach.Recommendation {
        NapCoach.recommend(
            now: now,
            debtMinutes: max(shortfallMinutes, 0),
            plannedBedtime: bedtime,
            napMinutesToday: napMinutesToday
        )
    }

    /// Below this, the window is treated as holding the need. Sleep need is
    /// itself an estimate to within tens of minutes.
    static let shortTolerance = 15.0

    /// How far the dragged window must differ from the reference before the
    /// comparative sentence is worth making.
    static let comparisonTolerance = 5.0

    /// One sentence about what this window does.
    ///
    /// Comparative when the person has actually moved something, because
    /// "6h 50m" alone does not say it is worse than what they had.
    func sentence(calendar: Calendar = .current) -> String {
        let window = SleepNightFeatures.formatMinutes(opportunityMinutes)
        if let reference,
           abs(reference.opportunityMinutes - opportunityMinutes) >= Self.comparisonTolerance {
            let direction = opportunityMinutes < reference.opportunityMinutes ? "falls to" : "rises to"
            let movedBedtime = abs(bedtime.timeIntervalSince(reference.bedtime)) >= Self.comparisonTolerance * 60
            let clause = movedBedtime
                ? "If you go to bed at \(clock(bedtime, calendar)) instead of \(clock(reference.bedtime, calendar))"
                : "If you wake at \(clock(wake, calendar)) instead of \(clock(reference.wake, calendar))"
            return "\(clause), your maximum sleep opportunity before a \(clock(wake, calendar)) wake time \(direction) \(window)."
        }
        if isShort {
            return "This window leaves room for \(window), which is \(SleepNightFeatures.formatMinutes(gapMinutes)) short of what you need."
        }
        return "This window leaves room for \(window), enough for what you need."
    }

    /// The consequences, as rows, in the order they happen.
    func rows(now: Date = .now, calendar: Calendar = .current) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let cutoff = caffeineCutoff(now: now) {
            rows.append(("Caffeine cutoff", clock(cutoff, calendar)))
        }
        rows.append(("Wind-down from", clock(windDown, calendar)))
        rows.append(("Sleep opportunity", SleepNightFeatures.formatMinutes(opportunityMinutes)))
        rows.append((
            "Against your need",
            gapMinutes >= Self.shortTolerance
                ? "−\(SleepNightFeatures.formatMinutes(gapMinutes))"
                : "covered"
        ))
        rows.append(("Morning light by", clock(morningLightUntil, calendar)))
        return rows
    }

    private func clock(_ date: Date, _ calendar: Calendar) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
