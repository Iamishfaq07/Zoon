import Foundation

/// Compact last-session troubleshooting copy. Not a score.
enum SleepToolReliability: Sendable {

    struct Line: Equatable, Sendable {
        let title: String
        let detail: String
    }

    static func lines(
        snoreMonitoredMinutes: Int?,
        snoreGapMinutes: Int?,
        snoreInterruptions: Int?,
        snorePartial: Bool,
        napMinutes: Int?,
        napWake: NapWakeKind?,
        soundsMinutes: Int?,
        soundsUninterrupted: Bool?
    ) -> [Line] {
        var out: [Line] = []
        if let minutes = soundsMinutes, minutes > 0 {
            let detail = soundsUninterrupted == false
                ? "\(minutes)m with an interruption"
                : "\(minutes)m uninterrupted"
            out.append(Line(title: "Sleep Sounds", detail: detail))
        }
        if let minutes = snoreMonitoredMinutes, minutes > 0 {
            var detail = "\(minutes)m monitored"
            if let count = snoreInterruptions, count > 0 {
                let gap = snoreGapMinutes.map { " · \($0)m gap" } ?? ""
                detail += " · \(count) interruption\(count == 1 ? "" : "s")\(gap)"
            }
            if snorePartial { detail += " · partial" }
            out.append(Line(title: "Snore Check", detail: detail))
        }
        if let minutes = napMinutes, minutes > 0, let wake = napWake {
            out.append(Line(title: "Nap", detail: "\(wake.historyLabel) · \(minutes) min"))
        }
        return out
    }
}
