import Foundation

/// Whether the numbers on the watch are about last night, or about a night
/// that has since been replaced.
///
/// The watch has no HealthKit pipeline of its own: everything it shows was
/// computed on the phone and sent across. That is a reasonable design, and
/// its failure mode is specific -- if the phone app has not been opened, the
/// watch keeps rendering the last snapshot it received, and renders it
/// exactly as confidently as a fresh one. Someone who slept last night and
/// glances at their wrist is shown the night before, with nothing anywhere
/// to say so.
///
/// The V9 spec asks for that case to be named rather than papered over.
///
/// ## What this deliberately does not do
///
/// The spec's own example pairs the refusal with a fresh figure read from
/// the watch's own HealthKit store -- "7h42 slept / Updating Zoon
/// Intelligence…". That half is **not** implemented here, and this type
/// cannot produce a duration. Reading sleep on the watch needs a HealthKit
/// entitlement, an explicit authorization flow, real-device testing and a
/// battery evaluation, and the spec is explicit that it must not be enabled
/// without validating watchOS's behaviour first. None of that can be done
/// from CI, so the honest half ships and the other half stays undone rather
/// than being guessed at.
///
/// The result is still worth having: not knowing last night's duration is a
/// gap, but showing the night before *as though it were* last night is a
/// wrong answer, and a gap beats a wrong answer.
enum SnapshotFreshness {

    /// How far behind the numbers are.
    enum State: Hashable, Sendable {
        /// The snapshot describes the most recent night there could be one
        /// for.
        case current
        /// It describes a night this many days older.
        case behind(nights: Int)

        var isCurrent: Bool { self == .current }
    }

    /// The hour by which a phone that has synced would have last night's
    /// numbers.
    ///
    /// Before this, a snapshot still describing yesterday is not evidence of
    /// anything: last night may simply not have been written to Health yet,
    /// or the sleeper may still be asleep. Calling that stale would fire the
    /// warning every single morning, and a warning that is always on is a
    /// warning nobody reads.
    static let settledHour = 10

    /// - Parameter now: the moment being rendered.
    static func state(
        of snapshot: SleepSnapshot,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> State {
        let nightDay = calendar.startOfDay(for: snapshot.date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: nightDay, to: today).day ?? 0

        // A snapshot dated in the future is not stale -- it is a clock
        // disagreement, most likely a timezone change mid-flight, and
        // shouting about freshness is the wrong response to it.
        guard days > 0 else { return .current }

        if days == 1, calendar.component(.hour, from: now) < settledHour {
            return .current
        }
        return .behind(nights: days)
    }

    /// What to tell the reader, or `nil` when there is nothing to say.
    ///
    /// Deliberately does not say "updating". Nothing is updating: the phone
    /// app has not run, and the watch cannot make it run. Copy that implies
    /// work is underway would have someone wait for a refresh that is not
    /// coming.
    static func note(for state: State) -> String? {
        switch state {
        case .current:
            return nil
        case .behind(let nights):
            let night = nights == 1 ? "night" : "nights"
            return "From \(nights) \(night) ago. Open Zoon on your phone to update."
        }
    }

    /// A short form, for a complication that has one line.
    static func shortNote(for state: State) -> String? {
        switch state {
        case .current: nil
        case .behind(let nights): "\(nights)d old"
        }
    }
}
