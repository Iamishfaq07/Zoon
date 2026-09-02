import SwiftUI

/// "What changed": this week against last, as a horizontal story stream of
/// three cells, each with a tiny visual signature -- a two-bar comparison
/// for the value, drawn in the metric's family colour -- instead of a card
/// of label/value rows.
///
/// The comparisons are the ones `WhatChangedCard` computed (time asleep,
/// HRV, bedtime steadiness, debt); the arithmetic is lifted verbatim so the
/// two can never disagree. Needs 14 nights; below that renders nothing.
struct WhatChangedStream: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double

    struct Change: Identifiable {
        let id: String
        let title: String
        let sentence: String
        let technical: String
        let before: Double
        let after: Double
        let tint: Color
        let isImprovement: Bool?
    }

    private var currentWeek: [SleepNightFeatures] { Array(nights.suffix(7)) }
    private var previousWeek: [SleepNightFeatures] { Array(nights.dropLast(7).suffix(7)) }

    var changes: [Change] {
        guard currentWeek.count == 7, previousWeek.count == 7 else { return [] }
        var result: [Change] = []

        let sleepBefore = average(previousWeek.map(\.timeAsleepMinutes))
        let sleepAfter = average(currentWeek.map(\.timeAsleepMinutes))
        let sleepDelta = sleepAfter - sleepBefore
        result.append(Change(
            id: "sleep", title: "Time asleep",
            sentence: sleepDelta == 0 ? "About the same as last week" : "\(Self.minutes(abs(sleepDelta))) \(sleepDelta > 0 ? "more" : "less") per night than last week",
            technical: "\(Self.minutes(sleepAfter)) vs \(Self.minutes(sleepBefore)) average",
            before: sleepBefore, after: sleepAfter,
            tint: Theme.Family.sleep, isImprovement: sleepDelta == 0 ? nil : sleepDelta > 0
        ))

        let hrvBefore = previousWeek.compactMap(\.avgHRV)
        let hrvAfter = currentWeek.compactMap(\.avgHRV)
        if hrvBefore.count >= 2, hrvAfter.count >= 2 {
            let b = average(hrvBefore), a = average(hrvAfter)
            let delta = a - b
            result.append(Change(
                id: "hrv", title: "HRV",
                sentence: abs(delta) < 1 ? "Steady against last week" : "\(delta > 0 ? "Up" : "Down") \(Int(abs(delta).rounded())) ms from last week",
                technical: "\(Int(a.rounded())) vs \(Int(b.rounded())) ms average",
                before: b, after: a,
                tint: Theme.Family.bodySignals, isImprovement: abs(delta) < 1 ? nil : delta > 0
            ))
        }

        let sdBefore = bedtimeStandardDeviationMinutes(previousWeek)
        let sdAfter = bedtimeStandardDeviationMinutes(currentWeek)
        let consistencyDelta = sdBefore - sdAfter
        result.append(Change(
            id: "bedtime", title: "Bedtime",
            sentence: abs(consistencyDelta) < 1 ? "As consistent as last week" : "\(Int(abs(consistencyDelta).rounded()))m \(consistencyDelta > 0 ? "more consistent" : "more scattered") than last week",
            technical: "±\(Int(sdAfter.rounded()))m vs ±\(Int(sdBefore.rounded()))m spread",
            // Lower spread is better, so flip for the bars: taller = steadier.
            before: max(0, 120 - sdBefore), after: max(0, 120 - sdAfter),
            tint: Theme.Family.circadian, isImprovement: abs(consistencyDelta) < 1 ? nil : consistencyDelta > 0
        ))

        let series = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: nights.map(\.total24hAsleepMinutes),
            goalMinutesOldestFirst: nights.map { $0.sleepNeedBaselineMinutes ?? goalMinutes }
        )
        if series.count >= 14, let debtNow = series.last, let debtWeekAgo = series.dropLast(7).last {
            let delta = debtNow - debtWeekAgo
            result.append(Change(
                id: "debt", title: "Sleep debt",
                sentence: abs(delta) < 1 ? "Unchanged from last week" : "\(delta < 0 ? "Down" : "Up") \(Self.minutes(abs(delta))) from last week",
                technical: "\(Self.minutes(debtNow)) owed now, \(Self.minutes(debtWeekAgo)) a week ago",
                before: debtWeekAgo, after: debtNow,
                tint: Theme.Family.attention, isImprovement: abs(delta) < 1 ? nil : delta < 0
            ))
        }

        return Array(result.prefix(3))
    }

    var body: some View {
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ZoonSectionHeader("What changed") {
                    Text("This week vs last")
                        .font(Theme.text(11))
                        .foregroundStyle(.tertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(changes) { change in
                            ChangeCell(change: change)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func minutes(_ value: Double) -> String {
        SleepNightFeatures.formatMinutes(value)
    }

    /// Same convention as `WhatChangedCard` and `ConsistencyChartCard`.
    private func bedtimeStandardDeviationMinutes(_ week: [SleepNightFeatures]) -> Double {
        var calendar = Calendar.current
        let minutesFromMidnight = week.map { night -> Double in
            calendar.timeZone = night.timeZone
            let components = calendar.dateComponents([.hour, .minute], from: night.bedtime)
            let minutes = Double(components.hour ?? 0) * 60 + Double(components.minute ?? 0)
            return minutes >= 18 * 60 ? minutes - 24 * 60 : minutes
        }
        guard minutesFromMidnight.count > 1 else { return 0 }
        let mean = average(minutesFromMidnight)
        let variance = minutesFromMidnight.reduce(0) { $0 + pow($1 - mean, 2) } / Double(minutesFromMidnight.count)
        return variance.squareRoot()
    }
}

/// One cell of the stream: title, two-bar before/after signature, sentence,
/// and the technical line beneath in the evidence style.
private struct ChangeCell: View {
    let change: WhatChangedStream.Change
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(change.title)
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            bars

            Text(change.sentence)
                .font(Theme.label(14, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Text(change.technical)
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(width: 200, alignment: .leading)
        .drawOnce(id: change.id + change.technical, progress: $progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(change.title). \(change.sentence). \(change.technical)")
    }

    private var bars: some View {
        let peak = max(change.before, change.after, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            bar(fraction: change.before / peak, tint: change.tint.opacity(0.35), label: "Last week")
            bar(fraction: change.after / peak, tint: change.tint, label: "This week")
            Spacer(minLength: 0)
            if let isImprovement = change.isImprovement {
                Image(systemName: isImprovement ? "arrow.up.right" : "arrow.down.right")
                    .font(Theme.text(11, weight: .bold))
                    .foregroundStyle(isImprovement ? Theme.Family.recovery : Theme.Family.attention)
                    .padding(.bottom, 2)
            }
        }
        .frame(height: 36)
    }

    private func bar(fraction: Double, tint: Color, label: String) -> some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 22, height: max(4, 30 * fraction * progress))
        }
        .frame(height: 36, alignment: .bottom)
    }
}

#Preview("What changed stream") {
    ScrollView {
        WhatChangedStream(nights: MockData.history, goalMinutes: 480)
            .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
