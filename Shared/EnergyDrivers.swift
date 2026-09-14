import Foundation

/// Why Energy is where it is, attributed to things that happened.
///
/// **Why this and not a Readiness score.** The brief asks whether a
/// "Readiness Now" number — capacity right now, after today's activity and
/// physiology — adds information Zoon does not already carry. It does not.
/// Energy *is* that model: an accounting curve that starts from the night's
/// recovery and drains hour by hour with heart rate. A second score built
/// from the same inputs would need its own weights for how much an hour of
/// effort costs this person's capacity, and nothing in the data calibrates
/// them. Ungrounded weights dressed as a number is the shape of the
/// Cardiovascular Age this app has already deleted once.
///
/// What the Readiness idea genuinely adds is not the number — it is the
/// sentence underneath it: *down 18 since waking, because of the afternoon
/// run*. Energy already knows that and never said it. This attributes the
/// change to what caused it, from data already computed.
///
/// Nothing here is a new measurement. Every point attributed below is a drain
/// the curve had already recorded; this only says which hour it happened in
/// and what was happening then.
///
/// One consequence worth stating: attributed drain can exceed the net fall
/// since waking, because quiet hours in between charge some of it back. A run
/// that cost 18 on a day that recovered 4 afterwards is still a run that cost
/// 18, and rounding it down to the net figure would understate what the
/// activity actually took.
enum EnergyDrivers {

    /// A period the caller can name — a workout, typically. Kept
    /// framework-free so the engine stays in `Shared`; the app maps its own
    /// `WorkoutSummary` onto this, the same way `WorkoutDeduplicator` is fed.
    struct NamedInterval: Hashable, Sendable {
        let label: String
        let symbol: String
        let start: Date
        let end: Date

        init(label: String, symbol: String, start: Date, end: Date) {
            self.label = label
            self.symbol = symbol
            self.start = start
            self.end = end
        }

        func covers(_ date: Date) -> Bool { date >= start && date < end }
    }

    struct Driver: Hashable, Sendable, Identifiable {
        let label: String
        let symbol: String
        /// Energy points attributed. Always positive — the direction is in
        /// the word "spent", not in the sign.
        let spent: Int

        var id: String { label }
    }

    enum State: Equatable, Sendable {
        /// Not enough of the curve to attribute anything yet — too early in
        /// the day, or a battery with nothing behind it.
        case notEnoughYet
        /// The curve exists and has barely moved.
        case steady(spent: Int)
        case explained(spent: Int, drivers: [Driver])

        var spent: Int {
            switch self {
            case .notEnoughYet: 0
            case .steady(let spent): spent
            case .explained(let spent, _): spent
            }
        }
    }

    /// Below this the change is not worth explaining; a few points of drift
    /// over a morning is the curve breathing, not a story.
    static let minimumSpendToExplain = 5
    /// Hours draining at least this much are the ones worth naming. Below it
    /// the drain is ordinary waking metabolism, which is not a driver.
    static let notableHourlyDrain: Double = 3

    /// - Parameters:
    ///   - battery: the day's curve, oldest point first.
    ///   - workouts: named periods to attribute hours to.
    ///   - isPresentable: whether the battery's own provenance allows a
    ///     number to be stated at all. A drain attributed from a curve that
    ///     may not be shown is a number smuggled past its own gate.
    static func explain(
        battery: BodyBattery,
        workouts: [NamedInterval],
        isPresentable: Bool
    ) -> State {
        guard isPresentable, battery.points.count >= 2 else { return .notEnoughYet }

        let spent = battery.spentToday
        guard spent >= minimumSpendToExplain else { return .steady(spent: spent) }

        var byWorkout: [String: (symbol: String, drain: Double)] = [:]
        var otherNotableDrain: Double = 0

        for point in battery.points where point.delta < 0 {
            let drain = -point.delta
            // An hour belongs to a workout when the workout was running at
            // any point in it. Hours are the finest resolution the curve has,
            // so a 20-minute session claims its whole hour -- stated rather
            // than silently apportioned, because splitting it would invent a
            // precision the curve does not have.
            if let workout = workouts.first(where: {
                $0.covers(point.date) || ($0.start >= point.date && $0.start < point.date.addingTimeInterval(3600))
            }) {
                let existing = byWorkout[workout.label]
                byWorkout[workout.label] = (workout.symbol, (existing?.drain ?? 0) + drain)
            } else if drain >= notableHourlyDrain {
                otherNotableDrain += drain
            }
        }

        var drivers = byWorkout
            .map { Driver(label: $0.key, symbol: $0.value.symbol, spent: Int($0.value.drain.rounded())) }
            .filter { $0.spent > 0 }
            .sorted { $0.spent > $1.spent }

        let other = Int(otherNotableDrain.rounded())
        if other > 0 {
            drivers.append(Driver(label: "Active hours", symbol: "figure.walk", spent: other))
        }

        // Nothing stood out: the day drained evenly, which is a real answer
        // and not a failure to attribute.
        guard !drivers.isEmpty else { return .steady(spent: spent) }
        return .explained(spent: spent, drivers: drivers)
    }
}

extension EnergyDrivers.State {

    /// The one line a card shows. Never claims to have explained a change it
    /// did not attribute.
    var headline: String {
        switch self {
        case .notEnoughYet:
            "Not enough of today yet"
        case .steady(let spent):
            spent == 0 ? "Level since waking" : "Down \(spent) since waking"
        case .explained(let spent, _):
            "Down \(spent) since waking"
        }
    }

    var drivers: [EnergyDrivers.Driver] {
        if case .explained(_, let drivers) = self { return drivers }
        return []
    }
}
