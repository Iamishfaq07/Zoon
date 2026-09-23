import Foundation

/// What saving a night's times would actually queue, before it is saved.
///
/// The editor used to accept a bed and wake and say only "reminders and the
/// alarm follow these times" -- without saying which reminders were on,
/// whether iOS allowed them, or that a wind-down 30 minutes before an
/// already-close bedtime would simply not be sent. This lists each item the
/// scheduler would queue for that night, at the time it would fire, and says
/// plainly when something will not happen and why.
///
/// The lead times live here and the scheduler reads them from here, so the
/// preview cannot describe a different offset from the one that is queued.
enum SchedulePreview {
    /// Wind-down nudge, before bedtime.
    static let windDownLeadMinutes = 30
    /// Wake-window notification, before the wake.
    static let wakeWindowLeadMinutes = 20
    /// Morning brief, after the wake.
    static let morningBriefDelayMinutes = 30

    struct Settings: Equatable, Sendable {
        var bedtimeReminders: Bool
        var wakeWindow: Bool
        var wakeAlarm: Bool
        var morningBrief: Bool
        /// iOS notifications are denied or not yet asked for.
        var notificationsBlocked: Bool
        /// The alarm needs a permission or is unavailable on this device.
        var alarmBlocked: Bool
    }

    static func lines(
        bed: Date,
        wake: Date,
        settings: Settings,
        isSkipped: Bool = false,
        now: Date,
        timeText: (Date) -> String
    ) -> [String] {
        if isSkipped {
            return ["Reminders and the alarm are skipped for this night, so nothing will be scheduled."]
        }
        var lines: [String] = []

        func notification(_ label: String, at date: Date, enabled: Bool) {
            guard enabled else { return }
            if settings.notificationsBlocked {
                lines.append("\(label): not sent, notifications are off for Zoon in iOS Settings.")
            } else if date <= now {
                lines.append("\(label): not sent, \(timeText(date)) has already passed.")
            } else {
                lines.append("\(label) notification at \(timeText(date)).")
            }
        }

        notification("Wind-down", at: bed.addingTimeInterval(-Double(windDownLeadMinutes) * 60), enabled: settings.bedtimeReminders)
        notification("Bedtime", at: bed, enabled: settings.bedtimeReminders)
        notification("Wake window", at: wake.addingTimeInterval(-Double(wakeWindowLeadMinutes) * 60), enabled: settings.wakeWindow)

        // The alarm rides on the wake window, as in the scheduler.
        if settings.wakeWindow && settings.wakeAlarm {
            if settings.alarmBlocked {
                lines.append("Alarm: not set, Zoon does not have permission to set alarms.")
            } else if wake <= now {
                lines.append("Alarm: not set, \(timeText(wake)) has already passed.")
            } else {
                lines.append("Alarm rings at \(timeText(wake)), even in Silent mode.")
            }
        }

        notification("Morning brief", at: wake.addingTimeInterval(Double(morningBriefDelayMinutes) * 60), enabled: settings.morningBrief)

        if lines.isEmpty {
            return ["Nothing will be scheduled: bedtime reminders, the wake window and the morning brief are all off in Settings."]
        }
        return lines
    }

    /// Bed and wake as they would fall for a one-night plan ending on
    /// `morning`: the wake on that morning, the bed at the latest time with
    /// that clock reading before it. Clock pickers keep the original date,
    /// so a bedtime moved past midnight would otherwise land a day early.
    static func resolve(
        bedClock: Date,
        wakeClock: Date,
        morning: Date,
        calendar: Calendar = .current
    ) -> (bed: Date, wake: Date) {
        func clock(_ date: Date, on day: Date) -> Date {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? day
        }
        let morningDay = calendar.startOfDay(for: morning)
        let wake = clock(wakeClock, on: morningDay)
        var bed = clock(bedClock, on: morningDay)
        if bed >= wake {
            bed = calendar.date(byAdding: .day, value: -1, to: bed) ?? bed
        }
        return (bed, wake)
    }
}
