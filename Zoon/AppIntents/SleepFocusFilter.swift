import AppIntents

/// Lets a Focus tell Zoon that you have already decided to go to bed.
///
/// The one system integration a sleep app most obviously owes its users, and
/// the app had none. Sleep Focus is an explicit statement of intent — "I am
/// going to bed now" — and Zoon's own wind-down nudge is a *guess* at the same
/// thing, derived from `BodyClock` and fired 30 minutes ahead on a schedule
/// set hours earlier. When the two disagree, the person is right and the
/// schedule is wrong.
///
/// So while a Focus carrying this filter is on, the pre-scheduled wind-down
/// and bedtime notifications are cancelled. Telling someone who has just
/// switched on Sleep Focus to "put the screens away in 30 minutes" is the kind
/// of notification that teaches people to turn all of them off.
///
/// Deliberately narrow. It doesn't pause tracking, change the score, or touch
/// the wake alarm: an alarm exists precisely to fire through a Focus, and
/// silencing it here would be the reverse of what the user asked for.
///
/// Attaches to *any* Focus, not just Sleep — someone whose wind-down actually
/// begins with a "Reading" or "Personal" Focus gets the same benefit, and the
/// system already lets them choose which.
struct SleepFocusFilter: SetFocusFilterIntent {

    static var title: LocalizedStringResource = "Silence Zoon's bedtime nudges"

    static var description: IntentDescription? = IntentDescription(
        """
        While this Focus is on, Zoon won't send its wind-down or bedtime \
        reminders — you've already said you're going to bed. Sleep tracking \
        and your wake alarm are unaffected.
        """
    )

    /// A parameter rather than an implicit always-on behaviour, because the
    /// system shows it in the Focus setup screen — which is the only place
    /// this feature is discoverable at all.
    @Parameter(title: "Silence bedtime nudges", default: true)
    var silencesBedtimeNudges: Bool

    /// What the Focus settings screen shows for the configured filter.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: silencesBedtimeNudges
                ? "Bedtime nudges silenced"
                : "Bedtime nudges as normal"
        )
    }

    /// Called by the system when the Focus turns on, and again when its
    /// configuration changes.
    ///
    /// Cancelling here rather than only setting the flag matters: the
    /// notifications are *already scheduled* with the system by the time a
    /// Focus activates, so a flag alone would change nothing until the app
    /// next ran. Re-arming when the filter is switched off is left to
    /// `RootView.refreshReminders`, which already re-computes the target
    /// bedtime from current data on every foreground — a stale bedtime
    /// re-armed from here would be worse than a slightly late one.
    @MainActor
    func perform() async throws -> some IntentResult {
        let preferences = UserPreferences()
        preferences.focusSilencesBedtimeNudges = silencesBedtimeNudges

        if silencesBedtimeNudges {
            BedtimeReminder().cancel()
        }

        return .result()
    }
}
