import Foundation

/// The moon's actual phase on a given date.
///
/// Every moon Zoon drew sat at one fixed phase, in an app named for the
/// moon. This is the real one, from the mean synodic month counted from a
/// known new moon. The mean month ignores the wobble in the moon's orbit, so
/// the instant of a phase can be off by up to about half a day -- far finer
/// than a drawn moon or a phase name can show, and it needs no network, no
/// location and no ephemeris.
struct LunarPhase: Equatable, Sendable {

    /// Position in the cycle: 0 at new moon, 0.5 at full, back to 1 at new.
    let cycle: Double

    /// Days in a mean synodic month.
    static let synodicDays = 29.530588853

    /// New moon of 6 January 2000, 18:14 UTC.
    private static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    init(cycle: Double) {
        let wrapped = cycle.truncatingRemainder(dividingBy: 1)
        self.cycle = wrapped < 0 ? wrapped + 1 : wrapped
    }

    init(date: Date = .now) {
        let days = date.timeIntervalSince(Self.referenceNewMoon) / 86_400
        self.init(cycle: days / Self.synodicDays)
    }

    /// Lit fraction of the disc, 0 at new and 1 at full.
    var illumination: Double {
        (1 - cos(2 * .pi * cycle)) / 2
    }

    /// Growing towards full. Decides which limb is lit.
    var isWaxing: Bool { cycle < 0.5 }

    /// The eight traditional names. New, full and the quarters each get a
    /// narrow band around their instant; the four between take the rest.
    var name: String {
        switch cycle {
        case ..<0.03, 0.97...: "New moon"
        case ..<0.22: "Waxing crescent"
        case ..<0.28: "First quarter"
        case ..<0.47: "Waxing gibbous"
        case ..<0.53: "Full moon"
        case ..<0.72: "Waning gibbous"
        case ..<0.78: "Last quarter"
        default: "Waning crescent"
        }
    }

    /// "Waxing gibbous, 78% lit", for a caption or VoiceOver.
    var summary: String {
        "\(name), \(Int((illumination * 100).rounded()))% lit"
    }
}

/// The brightening before a wake time: 0 while it is still night, rising to
/// 1 at the wake. Dawn simulation -- light that grows gradually before
/// waking -- is the one alarm that starts working before it goes off.
enum DawnRamp {

    /// How long before the wake the light starts to grow.
    static let leadMinutes: Double = 20

    /// 0 until `leadMinutes` before `wake`, then a smooth rise to 1 at the
    /// wake, held at 1 for half an hour after, and 0 again beyond that so a
    /// clock left open all day does not stay lit.
    static func progress(now: Date, wake: Date?) -> Double {
        guard let wake else { return 0 }
        let minutesToWake = wake.timeIntervalSince(now) / 60
        if minutesToWake > leadMinutes || minutesToWake < -30 { return 0 }
        if minutesToWake <= 0 { return 1 }
        let linear = 1 - minutesToWake / leadMinutes
        // Ease in: the first minutes barely change, as a real dawn does.
        return linear * linear
    }
}
