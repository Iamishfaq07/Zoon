import Foundation

extension SchedulePreview.Settings {
    /// The same switches `RootView.refreshReminders` reads, and the
    /// permission state its last reconciliation recorded. A Focus that
    /// silences bedtime nudges counts as bedtime reminders off, as it does
    /// there.
    @MainActor
    static func current(_ preferences: UserPreferences, store: ScheduleStateStore = ScheduleStateStore()) -> Self {
        func blocked(_ slot: ScheduleStateStore.Slot) -> Bool { store.entry(slot).status == .needsPermission }
        return Self(
            bedtimeReminders: preferences.bedtimeRemindersEnabled && !preferences.focusSilencesBedtimeNudges,
            wakeWindow: preferences.smartWakeEnabled,
            wakeAlarm: preferences.wakeAlarmEnabled,
            morningBrief: preferences.morningBriefEnabled,
            notificationsBlocked: blocked(.bedtime) || blocked(.wakeWindow) || blocked(.morningBrief),
            alarmBlocked: blocked(.wakeAlarm)
        )
    }
}
