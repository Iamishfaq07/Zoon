import Foundation

/// The whole morning in three lines: how you slept, how your body reads, and
/// what to do about today.
///
/// ## The problem it solves
///
/// Today had become a good screen that asks a lot. The hero alone puts a
/// score, a band, a confidence, a data-coverage percentage, seven component
/// arcs and a legend in front of someone who has just woken up. Every one of
/// those is defensible on its own; together they are a dashboard, and a
/// dashboard makes the reader do the summarising.
///
/// So the default answer comes first and the explanation waits behind a tap.
/// MEANING, then NUMBER, then METHOD -- the same order `SensorTruth` and the
/// Evidence screen already use, applied to the screen people actually open.
///
/// ## Why the copy lives here rather than in the view
///
/// Because it makes claims. "You're about 1h35 behind your estimated sleep
/// need" is a statement about someone's data with a threshold behind it, and
/// thresholds that live in a `Text(...)` are thresholds nobody tests. Every
/// sentence this produces is assembled here and asserted in
/// `MorningInThreeTests`.
struct MorningInThree: Sendable, Hashable {

    struct Line: Sendable, Hashable, Identifiable {
        /// SLEEP / BODY / TODAY.
        let label: String
        /// The answer, large.
        let headline: String
        /// One sentence of context, or nil when the headline says it all.
        let detail: String?

        var id: String { label }
    }

    let sleep: Line
    let body: Line
    let today: Line

    var lines: [Line] { [sleep, body, today] }

    /// Debt below this is not worth opening the day with. Two thirds of an
    /// hour is roughly one short night, and anything under it is inside the
    /// noise of estimating a sleep need at all -- reporting it would give the
    /// reader a number to chase that Zoon cannot actually resolve.
    static let debtWorthMentioningMinutes = 40.0

    /// - Parameters:
    ///   - bodySignalsHeadline: `HealthRadar`'s own sentence when it has
    ///     something to say. `nil` means nothing unusual, which is the
    ///     common case and gets said plainly rather than left blank.
    ///   - debtMinutes: accumulated shortfall against this person's own need.
    ///   - hasEnoughHistoryForNeed: false while the sleep need is still the
    ///     Settings default rather than something learned. The TODAY line
    ///     stops making a claim about a shortfall it cannot yet size.
    static func build(
        timeAsleepMinutes: Double,
        flagshipScore: Int,
        flagshipBand: String,
        bodySignalsHeadline: String?,
        debtMinutes: Double,
        hasEnoughHistoryForNeed: Bool
    ) -> MorningInThree {

        let sleep = Line(
            label: "SLEEP",
            headline: SleepNightFeatures.formatMinutes(timeAsleepMinutes),
            detail: flagshipBand.isEmpty ? nil : "\(flagshipBand) · \(flagshipScore)"
        )

        let body = Line(
            label: "BODY",
            headline: bodySignalsHeadline == nil ? "Signals look typical" : "Worth a look",
            detail: bodySignalsHeadline
        )

        let today: Line
        if !hasEnoughHistoryForNeed {
            // No claim about a shortfall while the need is still a default.
            // "You're 2h behind" against a number nobody measured is exactly
            // the sort of confident-sounding nonsense the rest of this app
            // refuses to print.
            today = Line(
                label: "TODAY",
                headline: "Still learning your sleep need",
                detail: "A few more nights and Zoon can tell you how far ahead or behind you are."
            )
        } else if debtMinutes >= debtWorthMentioningMinutes {
            today = Line(
                label: "TODAY",
                headline: "You're about \(SleepNightFeatures.formatMinutes(debtMinutes)) behind",
                // Names the goal, not the method. "An earlier night beats a
                // lie-in" is true of an office worker with a fixed alarm and
                // false of a night-shift nurse, someone mid-timezone-shift,
                // a parent whose evening is not theirs, or anyone on a
                // recovery day. Zoon knows the shortfall; it does not know
                // which end of the night is available, so it says what to
                // protect and leaves how to Autopilot, which does know.
                detail: "That's against your own estimated sleep need. Protecting enough sleep opportunity tonight is what closes it."
            )
        } else {
            today = Line(
                label: "TODAY",
                headline: "You're on top of your sleep need",
                detail: "Nothing to make up. Holding the same bedtime is what keeps it that way."
            )
        }

        return MorningInThree(sleep: sleep, body: body, today: today)
    }
}
