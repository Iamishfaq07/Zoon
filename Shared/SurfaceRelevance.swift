import Foundation

/// When each widget or complication is worth the Smart Stack's attention.
///
/// Every complication in the watch bundle used to share one relevance score,
/// computed purely from how recently the phone had sent a snapshot. That is
/// a freshness signal, not a relevance one: it says the data is current, and
/// says nothing about whether *this* number is the one someone wants right
/// now. With all four scoring identically, the Smart Stack had nothing to
/// order them by, which is the same as not implementing relevance at all.
///
/// The V9 spec asks for the obvious thing instead: last night and recovery
/// in the morning, body signals through the afternoon, tonight in the
/// evening, and the nap timer whenever a nap is actually running.
///
/// ## Why this is not called `WatchRelevance` any more
///
/// It was, and the name was the reason the same bug survived on iOS for a
/// release. The watch got per-surface relevance; the four iOS widgets kept
/// sharing one freshness score, which is the identical defect described
/// above, on the other platform. A shared type named after one of the two
/// platforms it serves invites exactly that -- the next person reads the
/// name, decides it does not apply to them, and writes a second table.
///
/// There is one table of day-parts now, and both platforms read it.
///
/// ## Why an hour and not a schedule
///
/// This deliberately keys off the wall clock rather than the person's own
/// body clock. `BodyClock` exists and would be more personal, but the watch
/// widget extension has no history to compute one from -- and a relevance
/// hint that is occasionally a bit early is a much smaller failure than a
/// widget surface that has to wait for a phone sync before it can rank
/// anything at all.
enum SurfaceRelevance {

    /// The surfaces that compete for a Smart Stack slot, on either platform.
    enum Kind: String, CaseIterable, Hashable, Sendable {
        case lastNight
        case recovery
        case bodySignals
        case tonight
        case napTimer
        /// Accumulated sleep debt.
        ///
        /// Evening, with `tonight`, because debt is the number that decides
        /// what time to go to bed -- it is a question about the night ahead,
        /// not a report on the one behind. Two surfaces sharing a window is
        /// fine: they are both evening-relevant and the system picks between
        /// them, which is a far better position than four surfaces sharing
        /// one score and the system picking at random all day.
        case sleepDebt
    }

    /// Windows, in local hours. Half-open: `start..<end`.
    static let morning = 5..<12
    static let afternoon = 12..<18
    static let evening = 18..<24

    /// Score when a complication is in its window, and when it is not.
    ///
    /// The out-of-window score is deliberately not zero. A complication
    /// scoring zero can be dropped entirely, and someone who checks their
    /// recovery at 9pm should still find it -- lower down, not absent.
    static let inWindowScore: Float = 85
    static let outOfWindowScore: Float = 20

    /// A running nap outranks everything.
    ///
    /// Not a matter of taste: it is the only surface here that is about
    /// something happening *now* rather than something already measured. A
    /// timer someone has to hunt for while it runs has failed at the one
    /// job a timer has.
    static let activeNapScore: Float = 100

    /// How long a relevance hint stands before watchOS asks again.
    static let duration: TimeInterval = 3 * 3600

    /// Whether `kind` is in its own part of the day.
    static func isInWindow(_ kind: Kind, hour: Int) -> Bool {
        switch kind {
        case .lastNight, .recovery: morning.contains(hour)
        case .bodySignals: afternoon.contains(hour)
        case .tonight, .sleepDebt: evening.contains(hour)
        // A nap timer has no hour of its own. It is relevant exactly while a
        // nap is running and irrelevant the rest of the time, which is a
        // fact about the nap, not about the clock.
        case .napTimer: false
        }
    }

    /// The Smart Stack score for `kind` at `date`.
    ///
    /// - Parameter isNapRunning: passed rather than read, because the widget
    ///   extension cannot observe a nap directly -- it only knows what the
    ///   last snapshot told it.
    static func score(
        for kind: Kind,
        at date: Date,
        isNapRunning: Bool = false,
        calendar: Calendar = .current
    ) -> Float {
        if kind == .napTimer {
            return isNapRunning ? activeNapScore : 0
        }
        // A running nap suppresses the rest rather than merely losing to
        // them: the stack has one slot in view, and during a nap that slot
        // belongs to the timer.
        if isNapRunning { return outOfWindowScore }

        let hour = calendar.component(.hour, from: date)
        return isInWindow(kind, hour: hour) ? inWindowScore : outOfWindowScore
    }
}
