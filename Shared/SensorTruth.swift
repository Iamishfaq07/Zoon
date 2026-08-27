import Foundation

/// What kind of claim each number in this app actually is.
///
/// `DataQuality` answers "how often did this metric show up?". This answers
/// a different and less comfortable question: "when it did show up, what
/// was it?" A wrist temperature is a thing a sensor measured. A REM
/// minute-count is a model's guess, produced by an algorithm inferring
/// brain state from wrist movement and pulse timing. Both render as a
/// number on a card, in the same font, and nothing on that card
/// distinguishes a reading from an inference.
///
/// That gap is not cosmetic. Someone who believes their deep-sleep figure
/// is measured will change their behaviour chasing it, and consumer
/// wearables classify sleep *stages* far less reliably than they classify
/// sleep from wake. The number moving is not strong evidence the underlying
/// thing moved.
///
/// ## Provenance propagates
///
/// The rule that makes this more than a glossary: **a number is never a
/// stronger kind of claim than the weakest thing it was computed from.**
/// Sleep debt is straightforward arithmetic, which looks like the solid end
/// of the scale -- until you notice both of its inputs are themselves
/// modelled. Arithmetic on two guesses is a guess. `provenance(of:)`
/// resolves that automatically from each quantity's declared inputs, so a
/// quantity cannot be presented as more solid than its ingredients by
/// anyone who forgets to think about it.
enum SensorTruth {

    /// What produced a number, strongest kind of claim first.
    enum Provenance: Int, Comparable, CaseIterable, Hashable, Sendable {
        /// A sensor reports this quantity directly.
        case measured = 3
        /// Arithmetic over measurements, with no model in the middle.
        case derived = 2
        /// A model's estimate from proxy signals. The number is a guess,
        /// however many decimal places it carries.
        case inferred = 1
        /// The person told us. Not weaker than a sensor at knowing what
        /// they did -- but it is memory, and it is not independent of what
        /// they believe about their sleep.
        case selfReported = 0

        static func < (a: Provenance, b: Provenance) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .measured: "Measured"
            case .derived: "Calculated"
            case .inferred: "Estimated"
            case .selfReported: "You told us"
            }
        }

        var explanation: String {
            switch self {
            case .measured: "A sensor recorded this directly."
            case .derived: "Arithmetic on things a sensor recorded."
            case .inferred: "A model's best guess from indirect signals."
            case .selfReported: "You logged this yourself."
            }
        }
    }

    /// The quantities Zoon puts in front of people.
    enum Quantity: String, CaseIterable, Identifiable, Hashable, Sendable {
        case timeAsleep, timeInBed, sleepEfficiency, sleepStages, wakeCount
        case heartRate, restingHeartRate, hrv, respiratoryRate
        case bloodOxygen, wristTemperature, breathingDisturbances
        case sleepNeed, sleepDebt, behaviourTags

        var id: String { rawValue }

        var label: String {
            switch self {
            case .timeAsleep: "Time asleep"
            case .timeInBed: "Time in bed"
            case .sleepEfficiency: "Sleep efficiency"
            case .sleepStages: "Sleep stages"
            case .wakeCount: "Times awake"
            case .heartRate: "Heart rate"
            case .restingHeartRate: "Resting heart rate"
            case .hrv: "Heart rate variability"
            case .respiratoryRate: "Respiratory rate"
            case .bloodOxygen: "Blood oxygen"
            case .wristTemperature: "Wrist temperature"
            case .breathingDisturbances: "Breathing disturbances"
            case .sleepNeed: "Your sleep need"
            case .sleepDebt: "Sleep debt"
            case .behaviourTags: "What you logged"
            }
        }

        /// What this quantity is before any propagation from its inputs.
        var declaredProvenance: Provenance {
            switch self {
            case .heartRate, .restingHeartRate, .hrv, .bloodOxygen, .wristTemperature:
                .measured
            case .timeInBed, .sleepEfficiency, .sleepDebt:
                .derived
            case .timeAsleep, .sleepStages, .wakeCount, .respiratoryRate,
                 .breathingDisturbances, .sleepNeed:
                .inferred
            case .behaviourTags:
                .selfReported
            }
        }

        /// What this quantity is computed from. Empty for anything read
        /// straight off a sensor or entered by the person.
        var inputs: [Quantity] {
            switch self {
            case .sleepEfficiency: [.timeAsleep, .timeInBed]
            case .sleepDebt: [.timeAsleep, .sleepNeed]
            case .sleepNeed: [.timeAsleep]
            default: []
            }
        }

        /// The specific thing this number is, said plainly.
        var whatItIs: String {
            switch self {
            case .timeAsleep:
                "An algorithm's classification of which minutes you were asleep, from wrist movement and pulse."
            case .timeInBed:
                "The span between when the watch decided you settled and when it decided you got up."
            case .sleepEfficiency:
                "Time asleep divided by time in bed."
            case .sleepStages:
                "A model's guess at light, deep and REM, from movement and beat-to-beat timing."
            case .wakeCount:
                "How many times the same model decided you had woken."
            case .heartRate:
                "Pulse, from light reflected off the blood in your wrist."
            case .restingHeartRate:
                "Your lowest sustained pulse while still."
            case .hrv:
                "The variation between consecutive heartbeats, in milliseconds."
            case .respiratoryRate:
                "Breaths per minute, read out of the shape of the pulse waveform."
            case .bloodOxygen:
                "How saturated your blood is with oxygen, from how it absorbs two colours of light."
            case .wristTemperature:
                "How far your wrist ran from its own overnight baseline. A difference, not a body temperature."
            case .breathingDisturbances:
                "A classification of interruptions to your breathing pattern."
            case .sleepNeed:
                "What your own history suggests you need, not a guideline figure."
            case .sleepDebt:
                "Shortfall against that need, accumulated."
            case .behaviourTags:
                "The behaviours you ticked off."
            }
        }

        /// What it cannot tell you. Every quantity has one; a limit left
        /// blank would read as "no limit", which is never true.
        var limit: String {
            switch self {
            case .timeAsleep:
                "Good at total sleep, less good at exactly when you drifted off or surfaced."
            case .timeInBed:
                "Reading in bed can look like being asleep, and lying still awake usually does."
            case .sleepEfficiency:
                "Inherits the uncertainty of both numbers it divides."
            case .sleepStages:
                "This is the softest number here. Stage classification from a wrist agrees with a sleep lab far less than sleep-versus-wake does. Watch the trend across weeks, not one night's split."
            case .wakeCount:
                "Brief wakings that you never noticed are routine, and short ones are easily missed or invented."
            case .heartRate:
                "Sampled, not continuous, and motion corrupts individual readings."
            case .restingHeartRate:
                "Shifts with illness, alcohol, heat and the day before it, not just fitness."
            case .hrv:
                "Very sensitive to when it was sampled and to posture. Single nights say little; the baseline is the signal."
            case .respiratoryRate:
                "Inferred from the pulse rather than from airflow."
            case .bloodOxygen:
                "Consumer pulse oximetry is not a medical measurement. Accuracy varies with fit, motion and skin tone, and it is not a screening tool."
            case .wristTemperature:
                "Room temperature and bedding move this as readily as you do."
            case .breathingDisturbances:
                "Not a diagnosis, and not a substitute for a sleep study."
            case .sleepNeed:
                "Learned from nights you actually had, so a long stretch of short nights drags it down."
            case .sleepDebt:
                "Arithmetic on two estimates. Treat the direction as meaningful and the exact number as not."
            case .behaviourTags:
                "As accurate as your memory, and only for nights you filled in."
            }
        }
    }

    struct Fact: Identifiable, Hashable, Sendable {
        let quantity: Quantity
        /// After propagation from inputs -- what the number honestly is.
        let provenance: Provenance
        /// What it was before propagation, when the two differ.
        let declaredProvenance: Provenance
        /// The inputs that dragged it down, if any did.
        let weakenedBy: [Quantity]

        var id: String { quantity.rawValue }
        var isWeakenedByItsInputs: Bool { provenance < declaredProvenance }

        var sentence: String {
            var text = "\(quantity.label): \(provenance.label.lowercased()). \(quantity.whatItIs)"
            if isWeakenedByItsInputs, let first = weakenedBy.first {
                text += " Shown as an estimate because \(first.label.lowercased()) is one."
            }
            return text + " \(quantity.limit)"
        }
    }

    // MARK: - Resolution

    /// The honest provenance of `quantity`: its own, capped by the weakest
    /// of everything it was computed from, recursively.
    static func provenance(of quantity: Quantity) -> Provenance {
        min(quantity.declaredProvenance,
            quantity.inputs.map(provenance(of:)).min() ?? .measured)
    }

    static func fact(for quantity: Quantity) -> Fact {
        let resolved = provenance(of: quantity)
        return Fact(
            quantity: quantity,
            provenance: resolved,
            declaredProvenance: quantity.declaredProvenance,
            weakenedBy: quantity.inputs.filter { provenance(of: $0) < quantity.declaredProvenance }
        )
    }

    /// Every quantity, softest claim first -- the numbers most in need of a
    /// caveat are the ones worth reading first.
    static var all: [Fact] {
        Quantity.allCases
            .map(fact(for:))
            .sorted { a, b in
                a.provenance != b.provenance
                    ? a.provenance < b.provenance
                    : a.quantity.rawValue < b.quantity.rawValue
            }
    }

    /// The facts behind one screen's worth of numbers, softest first.
    static func facts(for quantities: [Quantity]) -> [Fact] {
        let wanted = Set(quantities)
        return all.filter { wanted.contains($0.quantity) }
    }
}
