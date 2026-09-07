import SwiftUI
import WatchKit

/// Four pages, swiped horizontally -- the redesign spec's "glanceable"
/// count for the watch. This used to run to six: Sleep Intelligence,
/// Recovery, Sleep, a standalone Battery ring, Body Signals, and Badges.
/// Six full-bleed swipes is a lot to page through on a wrist, and two of
/// those six were already redundant or low-priority enough to fold in
/// rather than earn their own screen: Body Battery already appears as a
/// mini-stat on the Recovery page, and Body Signals plus Badges are both
/// "check occasionally," not "check every glance" information, so they now
/// share one combined page instead of two.
///
/// A `TabView` in page style rather than a list: on a watch, swiping between
/// full-bleed screens is faster than scrolling a list and tapping into detail,
/// and each page is sized to be legible without the wrist being still.
struct WatchRootView: View {

    @Environment(WatchLink.self) private var link
    @State private var showsQuickLog = false

    var body: some View {
        TabView {
            if let snapshot = link.snapshot {
                // First while it runs, and absent otherwise. Every other page
                // here grades a night that has already happened; this is the
                // only one about something in progress, and a timer someone
                // has to swipe past three pages to find has failed at the one
                // job a timer has.
                //
                // The complication has shown a running nap since the Smart
                // Stack surface was added. Tapping it opened an app with
                // nothing to say about the nap, which is the gap this closes.
                if snapshot.isNapRunning() {
                    NapPage(snapshot: snapshot)
                }
                if snapshot.scoreLightMode { ScoreLightSnapshotView(snapshot: snapshot) }
                else { LastNightPage(snapshot: snapshot); TodayPage(snapshot: snapshot) }
                // Tonight, not last night -- the only page here about a
                // night that has not happened yet, which is why it sits
                // after the two that grade the one that has. Gated on the
                // label being non-empty: snapshots written before these
                // fields existed decode with "", and a page that renders a
                // blank target is worse than one page fewer.
                if !snapshot.tonightTargetLabel.isEmpty
                    || !snapshot.tomorrowRangeLabel.isEmpty {
                    TonightPage(snapshot: snapshot)
                }
                LogPage()
                if !snapshot.scoreLightMode { MorePage(snapshot: snapshot) }
            } else {
                WaitingPage(isActivated: link.isActivated)
            }
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(Theme.watchBackground, for: .tabView)
        // Retained as a shortcut from any page, not as the only way in --
        // see `LogPage`. A gesture with no affordance is not a route
        // someone discovers.
        .onLongPressGesture {
            WKInterfaceDevice.current().play(.click)
            showsQuickLog = true
        }
        .sheet(isPresented: $showsQuickLog) {
            QuickLogView()
        }
    }
}

/// A nap in progress, on the wrist.
///
/// Reads only what the snapshot already carries. `napStartedAt` and
/// `napTargetEnd` are absolute instants, stored that way so any surface can
/// re-decide the state at its own moment rather than inherit the phone's --
/// the same property the complication relies on.
///
/// The countdown is `Text(timerInterval:)` rather than a computed number:
/// the system ticks it between renders, and a nap timer that updates only
/// when the view happens to redraw is a timer showing the wrong time.
struct NapPage: View {
    let snapshot: SleepSnapshot

    private var countdown: ClosedRange<Date>? {
        guard let end = snapshot.napTargetEnd, end > .now else { return nil }
        return Date.now...end
    }

    var body: some View {
        VStack(spacing: 8) {
            Label("Nap", systemImage: "powersleep")
                .font(Theme.label(13, weight: .semibold))
                .foregroundStyle(Theme.Metric.sleep)

            if let countdown {
                Text(timerInterval: countdown, countsDown: true)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .privacySensitive()
                Text("until your target")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
            } else {
                // Past the target but still inside the believable window --
                // see `SleepSnapshot.napBelievableAfterTarget`. Saying the
                // target has passed is honest; a negative countdown is not.
                Text("Past your target")
                    .font(Theme.label(15, weight: .semibold))
                Text("Still counted as a nap for a little longer.")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Tonight's target from `SleepAutopilot`, and tomorrow's range from
/// `UncertaintyForecast`.
///
/// Both arrive pre-formatted in the snapshot. The watch has no HealthKit
/// pipeline and no night history, so it could not run either engine even if
/// they were compiled in -- the same reason badges are evaluated on the
/// phone. What the watch does own is the decision about how much of it fits
/// on a 40mm screen, which is why the note is capped at two lines here
/// rather than truncated on the phone.
private struct TonightPage: View {
    let snapshot: SleepSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tonight", systemImage: snapshot.isTonightTargetHolding
                  ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(snapshot.isTonightTargetHolding
                                 ? Theme.Metric.recoveryHigh : Theme.Metric.sleep)

            if !snapshot.tonightTargetLabel.isEmpty {
                Text(snapshot.tonightTargetLabel)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(snapshot.tonightTargetNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !snapshot.tomorrowRangeLabel.isEmpty {
                Divider()
                Text(snapshot.tomorrowRangeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// Log from the wrist: the redesign spec's ask for Morning Check-In, Nap,
/// Caffeine, and Alcohol quick actions, reached by a long-press from any
/// page rather than their own dedicated swipe pages.
///
/// Sent over `WatchLink.sendQuickAction`, which queues via
/// `transferUserInfo` -- delivery is not immediate or confirmed back to the
/// watch, so every action here shows an optimistic local confirmation
/// (checkmark + haptic) rather than waiting on a round trip the phone might
/// not complete for hours if it's out of range.
struct QuickLogView: View {

    @Environment(WatchLink.self) private var link
    @Environment(\.dismiss) private var dismiss
    @State private var confirmedID: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Log") {
                    logRow(id: "alcohol", label: "Alcohol", symbol: "wineglass") {
                        link.sendQuickAction(.behaviorTag(rawValue: "alcohol"))
                    }
                    logRow(id: "caffeine", label: "Caffeine", symbol: "cup.and.saucer") {
                        link.sendQuickAction(.behaviorTag(rawValue: "caffeineLate"))
                    }
                }

                Section("Nap") {
                    ForEach([10, 20, 30], id: \.self) { minutes in
                        logRow(id: "nap\(minutes)", label: "\(minutes) min", symbol: "powersleep") {
                            link.sendQuickAction(.nap(minutes: minutes))
                        }
                    }
                }

                Section("Morning check-in") {
                    ForEach(1...5, id: \.self) { rawValue in
                        logRow(
                            id: "feeling\(rawValue)",
                            label: Self.feelingLabel(rawValue),
                            symbol: Self.feelingSymbol(rawValue)
                        ) {
                            link.sendQuickAction(.morningFeeling(rawValue: rawValue))
                        }
                    }
                }
            }
            .navigationTitle("Quick Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func logRow(id: String, label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            WKInterfaceDevice.current().play(.success)
            action()
            confirmedID = id
        } label: {
            HStack {
                Label(label, systemImage: symbol)
                Spacer()
                if confirmedID == id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Metric.recoveryHigh)
                }
            }
        }
    }

    static func feelingLabel(_ rawValue: Int) -> String {
        switch rawValue {
        case 1: "Terrible"
        case 2: "Poor"
        case 3: "Okay"
        case 4: "Good"
        default: "Great"
        }
    }

    static func feelingSymbol(_ rawValue: Int) -> String {
        switch rawValue {
        case 1: "face.dashed"
        case 2: "cloud.rain"
        case 3: "minus.circle"
        case 4: "sun.min"
        default: "sun.max"
        }
    }
}

/// Says when the numbers above are not about last night.
///
/// Renders nothing at all when they are, which is almost always -- this
/// exists for the case where the phone app has not been opened, and the
/// watch would otherwise present a two-day-old score with the same
/// confidence as a fresh one.
///
/// It does not say what last night actually was. The watch cannot know that
/// without its own HealthKit read, which V9 item 33 gates behind an
/// entitlement, an authorization flow, device testing and a battery
/// evaluation. Not knowing is a gap; showing the wrong night as though it
/// were last night is a wrong answer, and this fixes the second.
struct WatchFreshnessNote: View {
    let snapshot: SleepSnapshot
    var now: Date = .now

    var body: some View {
        if let note = SnapshotFreshness.note(for: SnapshotFreshness.state(of: snapshot, now: now)) {
            Text(note)
                .font(Theme.text(9))
                .foregroundStyle(Theme.Metric.recoveryMid)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(note)
        }
    }
}

/// PAGE 1 -- Last night, as one page.
///
/// Sleep Intelligence and the duration/debt readout used to be two separate
/// swipes showing two aspects of the same night. That is the shape of a
/// phone screen split across a watch: someone glancing at their wrist to ask
/// "how did I sleep" should not have to swipe to find out how long for.
///
/// The number is Sleep Intelligence (`flagshipScore`), so this page and the
/// complications answer with the same figure.
struct LastNightPage: View {

    let snapshot: SleepSnapshot

    private var tint: Color {
        switch snapshot.flagshipScore {
        case 80...: Theme.Metric.recoveryHigh
        case 60..<80: Theme.Metric.battery
        case 40..<60: Theme.Metric.recoveryMid
        default: Theme.Metric.recoveryLow
        }
    }

    private var debtTint: Color {
        snapshot.sleepDebtMinutes <= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid
    }

    /// Mirrors the same "Last Night"/"Last Sleep" switch `SleepScoreWidget`
    /// makes on `snapshot.isShiftWorkModeEnabled` -- the watch app is its own
    /// process with no `UserPreferences` access, which is exactly why that
    /// flag rides along on the snapshot itself.
    private var title: String {
        snapshot.isShiftWorkModeEnabled ? "LAST SLEEP" : "LAST NIGHT"
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(Theme.label(9, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: Double(snapshot.flagshipScore) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.5), radius: 5)

                VStack(spacing: -3) {
                    Text("\(snapshot.flagshipScore)")
                        .font(Theme.numeral(32))
                        .monospacedDigit()
                    Text("SLEEP")
                        .font(Theme.label(9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)

            Text(snapshot.flagshipBand)
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                WatchMiniStat(
                    value: SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes),
                    label: "asleep",
                    tint: Theme.Metric.sleep
                )
                WatchMiniStat(
                    value: snapshot.balanceLabel,
                    label: "bank",
                    tint: debtTint
                )
            }

            WatchFreshnessNote(snapshot: snapshot)

            if snapshot.isMock {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }
}

/// A number and its caption, sized for a wrist. Shared by the pages so the
/// two do not drift apart typographically.
struct WatchMiniStat: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: -1) {
            Text(value)
                .font(Theme.label(15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(Theme.text(9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// PAGE 2 -- Today: how recovered the body looks, and whether anything is
/// drifting.
///
/// Declines to state a number it cannot stand behind. `RecoveryScore`
/// already separates the score from the confidence in it (V9 item 4), and a
/// watch face reading "Recovery 66" off four nights asserts exactly as
/// firmly as one off a month. When the phone reports insufficient
/// confidence, the ring goes and the page says so instead -- the same
/// refusal the phone makes, carried to the wrist rather than quietly
/// dropped on the way.
struct TodayPage: View {

    let snapshot: SleepSnapshot

    /// Reads the same thresholds `RecoveryScore.Band` uses
    /// (`RecoveryScoreTests` covers those boundaries) rather than
    /// re-deriving them here, so the watch's ring colour can't silently
    /// drift out of sync with the score's own low/moderate/high definition.
    private var tint: Color {
        switch RecoveryScore.Band.forPercent(snapshot.recoveryPercent) {
        case .high: Theme.Metric.recoveryHigh
        case .moderate: Theme.Metric.recoveryMid
        case .low: Theme.Metric.recoveryLow
        }
    }

    private var signalsAreNormal: Bool { snapshot.bodySignalsLabel == "Nothing unusual" }

    var body: some View {
        VStack(spacing: 5) {
            Text("TODAY")
                .font(Theme.label(9, weight: .semibold))
                .foregroundStyle(.secondary)

            if snapshot.canStateRecovery {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: Double(snapshot.recoveryPercent) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: tint.opacity(0.5), radius: 5)

                    VStack(spacing: -3) {
                        Text("\(snapshot.recoveryPercent)")
                            .font(Theme.numeral(32))
                            .monospacedDigit()
                        Text("RECOVERY")
                            .font(Theme.label(9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Text("Recovery")
                        .font(Theme.label(14, weight: .semibold))
                    Text("Limited data")
                        .font(Theme.label(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(signalsAreNormal ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
                    .frame(width: 6, height: 6)
                Text("Signals")
                    .font(Theme.text(10))
                    .foregroundStyle(.secondary)
                Text(signalsAreNormal ? "Typical" : snapshot.bodySignalsLabel)
                    .font(Theme.label(11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)

            WatchFreshnessNote(snapshot: snapshot)

            if snapshot.isMock {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }
}

/// PAGE 4 -- Log.
///
/// A page, not a long press. The V9 spec is explicit: "Do not hide essential
/// logging only behind long press." A gesture with no affordance is not a
/// route someone discovers, and logging caffeine is not an expert action --
/// it is the thing that makes every association Zoon can later find
/// possible at all. Nothing gets correlated that was never recorded.
///
/// The long press is kept as a shortcut from any page, because it is genuinely
/// faster once you know it. It is no longer the only way in.
struct LogPage: View {

    @Environment(WatchLink.self) private var link
    @State private var showsFullLog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("LOG")
                    .font(Theme.label(9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let snapshot = link.snapshot,
                   !snapshot.questionTag.isEmpty, !snapshot.questionText.isEmpty {
                    OneQuestionCard(tag: snapshot.questionTag, question: snapshot.questionText)
                }

                QuickLogActions()

                Button {
                    WKInterfaceDevice.current().play(.click)
                    showsFullLog = true
                } label: {
                    Text("More")
                        .font(Theme.label(11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showsFullLog) {
            QuickLogView()
        }
    }
}

/// Tonight's one question, answerable in one tap.
///
/// The phone decides what to ask -- the ranking engine, the journal history
/// and `BehaviorTag` itself all live in the app target, none of which exist
/// here -- and sends the question text and the tag identifier on the
/// snapshot. This renders them and sends the answer back.
///
/// Yes and No both send, rather than No being a second press of Yes. The
/// watch does not know what state the tag is currently in, and a toggle would
/// therefore record whichever answer the phone's existing state implied
/// rather than the one that was pressed.
///
/// Nothing renders when there is no question, which is a state the phone
/// reaches deliberately: `AdaptiveJournal.question` returns nothing when the
/// only thing left to ask is one whose answer Zoon can already predict.
struct OneQuestionCard: View {

    let tag: String
    let question: String

    @Environment(WatchLink.self) private var link
    @State private var answered: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(Theme.text(13, weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let answered {
                Text(answered ? "Logged: yes" : "Logged: no")
                    .font(Theme.label(11, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
            } else {
                HStack(spacing: 5) {
                    answerButton("Yes", happened: true)
                    answerButton("No", happened: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.neutral(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.bottom, 2)
    }

    private func answerButton(_ title: String, happened: Bool) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            link.sendQuickAction(.behaviorAnswer(rawValue: tag, happened: happened))
            answered = happened
        } label: {
            Text(title)
                .font(Theme.label(12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(title), \(question)")
    }
}

/// The four things worth logging from a wrist, visible without a gesture.
///
/// Caffeine and alcohol send the same behaviour tags the phone's journal
/// uses; nap and feeling open the fuller list, because "how long" and "how
/// rested" are choices rather than single facts and guessing one on the
/// user's behalf would put a number in their history they never gave.
struct QuickLogActions: View {

    @Environment(WatchLink.self) private var link
    @State private var confirmedID: String?
    @State private var presented: Sheet?

    private enum Sheet: String, Identifiable {
        case nap, feeling
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                action(id: "caffeine", label: "Caffeine", symbol: "cup.and.saucer") {
                    link.sendQuickAction(.behaviorTag(rawValue: "caffeineLate"))
                }
                action(id: "alcohol", label: "Alcohol", symbol: "wineglass") {
                    link.sendQuickAction(.behaviorTag(rawValue: "alcohol"))
                }
            }
            HStack(spacing: 5) {
                action(id: "nap", label: "Nap", symbol: "powersleep") { presented = .nap }
                action(id: "feeling", label: "Feeling", symbol: "face.smiling") { presented = .feeling }
            }
        }
        .sheet(item: $presented) { sheet in
            switch sheet {
            case .nap: NapDurationSheet()
            case .feeling: MorningFeelingSheet()
            }
        }
    }

    private func action(
        id: String,
        label: String,
        symbol: String,
        perform: @escaping () -> Void
    ) -> some View {
        Button {
            WKInterfaceDevice.current().play(.success)
            perform()
            confirmedID = id
        } label: {
            VStack(spacing: 2) {
                Image(systemName: confirmedID == id ? "checkmark.circle.fill" : symbol)
                    .font(Theme.text(15, weight: .semibold))
                    .foregroundStyle(confirmedID == id ? Theme.Metric.recoveryHigh : Theme.Metric.sleep)
                Text(label)
                    .font(Theme.label(10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Log \(label)")
    }
}

/// Nap length, asked rather than assumed.
struct NapDurationSheet: View {
    @Environment(WatchLink.self) private var link
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach([10, 20, 30], id: \.self) { minutes in
                    Button("\(minutes) min") {
                        WKInterfaceDevice.current().play(.success)
                        link.sendQuickAction(.nap(minutes: minutes))
                        dismiss()
                    }
                }
            }
            .navigationTitle("Nap")
        }
    }
}

/// How rested, asked rather than assumed.
struct MorningFeelingSheet: View {
    @Environment(WatchLink.self) private var link
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(1...5, id: \.self) { rawValue in
                    Button {
                        WKInterfaceDevice.current().play(.success)
                        link.sendQuickAction(.morningFeeling(rawValue: rawValue))
                        dismiss()
                    } label: {
                        Label(
                            QuickLogView.feelingLabel(rawValue),
                            systemImage: QuickLogView.feelingSymbol(rawValue)
                        )
                    }
                }
            }
            .navigationTitle("Feeling")
        }
    }
}

/// Body Signals and Badges, stacked on one page rather than two -- both are
/// "check occasionally" information (whether anything is drifting from
/// baseline; how the reward progress is going), not "check every glance"
/// like the pages before it, so they share a swipe instead of each claiming
/// a full screen.
///
/// Energy and load moved here when Today was cut back to the two things the
/// V9 spec asks that page for. They are still worth having -- this is just
/// the page for things you check occasionally rather than every glance, and
/// nowhere else on the watch shows them.
struct MorePage: View {

    let snapshot: SleepSnapshot

    private var isNormal: Bool { snapshot.bodySignalsLabel == "Nothing unusual" }
    private var hasBadge: Bool { !snapshot.badgeTitle.isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: isNormal ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(Theme.text(20, weight: .medium))
                    .foregroundStyle(isNormal ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
                Text(snapshot.bodySignalsLabel)
                    .font(Theme.label(13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }

            Divider().overlay(Color.white.opacity(0.15))

            VStack(spacing: 4) {
                Image(systemName: hasBadge ? snapshot.badgeSymbol : "hexagon")
                    .font(Theme.text(20, weight: .medium))
                    .foregroundStyle(hasBadge ? Theme.Metric.recoveryMid : .secondary)
                Text(hasBadge ? snapshot.badgeTitle : "No badges yet")
                    .font(Theme.label(13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(snapshot.badgesUnlocked) of \(snapshot.badgesTotal)")
                    .font(Theme.label(10, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(Color.white.opacity(0.15))

            HStack(spacing: 10) {
                WatchMiniStat(
                    value: "\(snapshot.bodyBattery)",
                    label: "energy",
                    tint: Theme.Metric.battery
                )
                WatchMiniStat(
                    value: String(format: "%.1f", snapshot.strain),
                    label: "load",
                    tint: Theme.Metric.strain
                )
            }

            if !snapshot.headlineFindingText.isEmpty {
                Divider().overlay(Color.white.opacity(0.15))
                headlineFinding
            }

            if snapshot.isMock {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
    }

    /// The strongest thing Zoon believes, with the tier that earned it.
    ///
    /// The tier label is not decoration and is not optional: "Caffeine goes
    /// with shorter sleep" and "You tested this: caffeine goes with shorter
    /// sleep" are different claims, and the second is the only one this
    /// screen has room to justify. `EvidenceNotebook.glanceMinimumStrength`
    /// is what keeps the weakest two tiers off the wrist entirely -- their
    /// caveats do not fit here, and they are the tiers that need them.
    private var headlineFinding: some View {
        VStack(spacing: 3) {
            Text(snapshot.headlineFindingStrength.uppercased())
                .font(Theme.label(9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.Metric.recoveryHigh)
            Text(snapshot.headlineFindingText)
                .font(Theme.text(11))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.secondary)
        }
    }
}

/// Before the first snapshot arrives.
///
/// Says what to do rather than spinning. A watch app that shows a spinner
/// forever is indistinguishable from one that is broken, and the fix here is
/// genuinely "open the phone app once".
struct WaitingPage: View {

    let isActivated: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(Theme.text(26))
                .foregroundStyle(Theme.Metric.sleep)

            Text("Waiting for your phone")
                .font(Theme.label(13, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(isActivated
                 ? "Open Zoon on your iPhone once and last night will appear here."
                 : "Connecting…")
                .font(Theme.text(10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
    }
}

#Preview("Last night") {
    LastNightPage(snapshot: MockData.snapshotWithBadges)
}

#Preview("Today") {
    TodayPage(snapshot: MockData.snapshotWithBadges)
}

/// The state the V9 spec asks for by name: when the phone reports it cannot
/// stand behind the number, the watch says so rather than showing one.
#Preview("Today - limited data") {
    TodayPage(snapshot: {
        var snapshot = MockData.snapshotWithBadges
        snapshot.recoveryConfidence = MetricConfidence.insufficient.rawValue
        return snapshot
    }())
}

#Preview("More") {
    MorePage(snapshot: MockData.snapshotWithBadges)
}

/// With a headline finding. The page is a fixed-height watch screen with two
/// stacked blocks already, so this is where a third one either fits or does
/// not -- and the finding is the block whose length Zoon does not control.
#Preview("More - with a finding") {
    MorePage(snapshot: MockData.findingSnapshot)
}

/// The page the V9 spec insists exists: logging with a visible affordance,
/// not only behind a long press.
/// The state the note exists for. Previewed by moving the clock forward
/// rather than by relabelling a fresh snapshot: the mock night is current,
/// so a page preview called "stale" would simply be wrong.
#Preview("Freshness note") {
    VStack(spacing: 10) {
        WatchFreshnessNote(
            snapshot: MockData.snapshotWithBadges,
            now: Date().addingTimeInterval(3 * 86_400)
        )
        // Current: renders nothing, which is the case that has to stay
        // invisible.
        WatchFreshnessNote(snapshot: MockData.snapshotWithBadges)
    }
    .padding()
}

#Preview("Log") {
    LogPage()
        .environment(WatchLink())
}

#Preview("Waiting") {
    WaitingPage(isActivated: true)
}

#Preview("Quick Log") {
    QuickLogView()
        .environment(WatchLink())
}
