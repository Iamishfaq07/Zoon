import Foundation

/// Movement as context, never as a score input.
///
/// Missing is not zero: a nil step count is "not recorded", not a sedentary
/// day. The sentence compares *so far today* against *this weekday by this
/// time*, so a Monday morning is not judged against a Saturday afternoon.
///
/// **The §27 line this must not cross.** The brief is explicit that steps do
/// not go into Sleep Score or Recovery, and nothing here returns a number any
/// score reads. `Snapshot` is a sentence, a confidence and the figures behind
/// them; it is passed to screens and to the Coach, and to nothing that scores.
///
/// **What the refinement added.** The type carried `activeEnergyKcal` and then
/// discarded it — there was a literal `_ = activeEnergyKcal` in the builder, so
/// the field was on the struct, visible to callers, and part of no sentence.
/// §27 names five inputs; this now reads four of them (steps, active energy,
/// exercise minutes, workouts) and says which it has, rather than carrying
/// them silently. Distance is the fifth and is deliberately absent: see
/// `distanceNote`.
enum MovementContext {

    struct Snapshot: Hashable, Sendable {
        let stepsSoFar: Int?
        let typicalStepsByNow: Int?
        let percentVsTypical: Double?
        let activeEnergyKcal: Double?
        /// Apple Exercise Minutes so far today.
        var exerciseMinutes: Double?
        /// Workouts logged today. Zero is a real observation here — unlike a
        /// step count, "no workouts today" is something the store can say
        /// positively — so this is not optional.
        var workoutCount: Int = 0
        let weekday: Int
        let sentence: String
        let confidence: MetricConfidence
        let provenance: String

        /// The other measures, as one line, or nothing when none were
        /// recorded. Kept apart from `sentence` so a caller can show the
        /// comparison without the inventory.
        var detail: String? {
            var parts: [String] = []
            if let activeEnergyKcal, activeEnergyKcal >= 1 {
                parts.append("\(Int(activeEnergyKcal.rounded())) kcal active")
            }
            if let exerciseMinutes, exerciseMinutes >= 1 {
                parts.append("\(Int(exerciseMinutes.rounded())) exercise minutes")
            }
            if workoutCount > 0 {
                parts.append(workoutCount.pluralized("workout"))
            }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: " · ")
        }

        /// The brief's second example shape: a qualitative line for a surface
        /// with no room for figures — the Coach's answer, a driver row.
        /// Returns `nil` rather than guessing when there is no comparison to
        /// make, because "movement has been typical" and "we do not know" must
        /// not read the same.
        var shortLine: String? {
            guard let percentVsTypical else { return nil }
            let day = MovementContext.weekdayName(weekday)
            if abs(percentVsTypical) < 0.08 {
                return "Today's movement is about usual for a \(day)."
            }
            return percentVsTypical < 0
                ? "Today's movement has been lower than your usual \(day)."
                : "Today's movement has been higher than your usual \(day)."
        }
    }

    /// Why distance is not among the figures above.
    ///
    /// §27 lists walking/running distance, and HealthKit does carry it — but
    /// on a phone it is derived from the same step stream already reported
    /// here, scaled by an estimated stride. Printing both would show one
    /// measurement twice and imply two independent readings agreed. Distance
    /// becomes worth adding when it comes from a watch's own GPS, which is a
    /// provenance Zoon does not currently distinguish.
    static let distanceNote =
        "Distance is not shown separately: on a phone it is estimated from the same steps above."


    /// The smallest typical step count a percentage may be stated against.
    ///
    /// A ratio needs a denominator worth dividing by. On a real device this
    /// reported "3,173 steps so far, 2566% above your typical Tuesday by this
    /// time (119)" — arithmetically correct and completely useless: 119 steps
    /// is a Tuesday the phone spent on a desk, not a typical Tuesday, and a
    /// four-digit percentage reads as an alarm rather than as context.
    ///
    /// Below this the steps are still reported; only the comparison is
    /// withheld, because the comparison is the part that has no support.
    static let minimumComparableTypical = 400

    /// Above this fraction over baseline the sentence switches from a
    /// percentage to a multiple: "about 4× your typical Tuesday" rather than
    /// "300% above". Both say the same thing; only one is readable at a
    /// glance, and past roughly this point the percentage stops being a
    /// number people convert and starts being a number they recoil from.
    static let multipleThreshold = 3.0

    /// The matching slice of an earlier day: that day's midnight up to the
    /// same *wall-clock* time it is now.
    ///
    /// Time of day, not elapsed seconds. A day containing a DST transition is
    /// twenty-three or twenty-five hours long, so counting today's seconds
    /// since midnight into it lands an hour off: on the week after a
    /// spring-forward, "how much had I walked by 15:00" was answered against
    /// 14:00 on the comparison day, and an hour of somebody's walking went
    /// missing from the baseline they were measured against. In autumn it
    /// went the other way and the baseline gained an hour they had not been
    /// given credit for.
    ///
    /// `nil` when that clock time did not happen on that day -- 02:30 does not
    /// exist on the morning the clocks go forward. The day is then dropped
    /// rather than approximated, for the reason every other absence here is
    /// dropped: a day Zoon cannot measure the same slice of is not a day of
    /// no walking.
    static func comparableSlice(
        of day: Date,
        matching now: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        let start = calendar.startOfDay(for: day)
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)

        // Built from components and then checked, rather than with
        // `date(bySettingHour:…)`.
        //
        // That call is a *search*: given a clock time that does not exist on
        // the day asked about, `.strict` does not return nil -- it looks
        // forward, across day boundaries, for the next instant that matches,
        // and the answer comes back on a different day than the one handed
        // in. Constructing the components and verifying the result is
        // deterministic, does no searching, and says nil when it means nil.
        var components = calendar.dateComponents([.year, .month, .day], from: start)
        components.hour = time.hour ?? 0
        components.minute = time.minute ?? 0
        components.second = time.second ?? 0

        guard let end = calendar.date(from: components),
              // A skipped hour comes back shifted rather than refused, so the
              // clock time is read back and compared. This is the check that
              // drops the morning the clocks went forward.
              calendar.component(.hour, from: end) == components.hour,
              calendar.component(.minute, from: end) == components.minute,
              calendar.isDate(end, inSameDayAs: start),
              end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// - Parameters:
    ///   - stepsSoFar: HealthKit step count today, or `nil` if unauthorized
    ///     or not recorded. Never pass 0 to mean "unknown".
    ///   - typicalStepsByNow: median steps for this weekday at this hour
    ///     across prior weeks. `nil` until enough matching hours exist.
    static func snapshot(
        stepsSoFar: Int?,
        typicalStepsByNow: Int?,
        activeEnergyKcal: Double? = nil,
        exerciseMinutes: Double? = nil,
        workoutCount: Int = 0,
        weekday: Int,
        now: Date = .now
    ) -> Snapshot {
        let percent: Double?
        if let steps = stepsSoFar, let typical = typicalStepsByNow, typical > 0 {
            percent = (Double(steps) - Double(typical)) / Double(typical)
        } else {
            percent = nil
        }

        let sentence: String
        let confidence: MetricConfidence
        let provenance: String

        switch (stepsSoFar, typicalStepsByNow, percent) {
        case (nil, _, _):
            sentence = "Steps for today have not been recorded, so movement is unknown rather than low."
            confidence = .insufficient
            provenance = "Missing HealthKit step count"
        case (let steps?, nil, _):
            sentence = "\(format(steps)) steps so far. There is not yet a typical \(weekdayName(weekday)) by this time to compare with."
            confidence = .low
            provenance = "Today's steps only"
        // A typical of zero is a real observation -- a weekday this person
        // genuinely has not moved by this hour in the past -- but it makes
        // the percentage undefined, so `percent` is nil and the tuple fell
        // through to `default`, reporting *recorded* steps as unknown.
        // Missing is not zero was the principle; this was its mirror image,
        // zero treated as missing.
        case (let steps?, let typical?, nil) where typical == 0:
            sentence = steps == 0
                ? "No steps yet, and no steps by this time on a typical \(weekdayName(weekday)) either."
                : "\(format(steps)) steps so far. A typical \(weekdayName(weekday)) has none by this time, so there is no percentage to compare."
            confidence = .low
            provenance = "Today versus same weekday at this hour"
        // A denominator too small to divide by. Distinct from a zero typical
        // above: there *is* a baseline, it is simply too thin for a
        // percentage to mean anything.
        case (let steps?, let typical?, _) where typical < minimumComparableTypical:
            sentence = "\(format(steps)) steps so far. A typical \(weekdayName(weekday)) has only \(format(typical)) by this time, which is too few to compare against."
            confidence = .low
            provenance = "Today versus same weekday at this hour"
        // A real baseline that today has genuinely dwarfed. 25,000 steps
        // against a true 1,000-step Tuesday is 2400%, which is arithmetically
        // honest and still unreadable -- nobody parses a four-digit
        // percentage. A multiple is the same fact in a form that lands.
        case (let steps?, let typical?, let delta?) where delta >= multipleThreshold:
            let times = Double(steps) / Double(typical)
            sentence = "\(format(steps)) steps so far, about \(String(format: "%.0f", times))× your typical \(weekdayName(weekday)) by this time (\(format(typical)))."
            confidence = .moderate
            provenance = "Today versus same weekday at this hour"
        case (let steps?, let typical?, let delta?):
            let absPct = Int((abs(delta) * 100).rounded())
            if abs(delta) < 0.08 {
                sentence = "\(format(steps)) steps so far — close to your usual \(weekdayName(weekday)) by this time (\(format(typical)))."
                confidence = .moderate
            } else if delta < 0 {
                sentence = "\(format(steps)) steps so far, \(absPct)% below your typical \(weekdayName(weekday)) by this time (\(format(typical)))."
                confidence = .moderate
            } else {
                sentence = "\(format(steps)) steps so far, \(absPct)% above your typical \(weekdayName(weekday)) by this time (\(format(typical)))."
                confidence = .moderate
            }
            provenance = "Today versus same weekday at this hour"
        default:
            sentence = "Movement is unknown."
            confidence = .insufficient
            provenance = "Missing"
        }

        _ = now
        return Snapshot(
            stepsSoFar: stepsSoFar,
            typicalStepsByNow: typicalStepsByNow,
            percentVsTypical: percent,
            activeEnergyKcal: activeEnergyKcal,
            exerciseMinutes: exerciseMinutes,
            workoutCount: max(0, workoutCount),
            weekday: weekday,
            sentence: sentence,
            confidence: confidence,
            provenance: provenance
        )
    }

    private static func format(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }
}
