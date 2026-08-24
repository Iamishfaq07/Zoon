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
                // Leads the same way the phone's hero now does: "how did I
                // sleep" ahead of "how recovered does my body look".
                // Snapshots written before this field existed decode with
                // sleepIntelligenceBand == "" -- that's the one signal this
                // page has to fall back on Recovery leading instead, since a
                // percent of 0 with a real band is indistinguishable from a
                // genuine (if unlikely) rock-bottom score.
                if !snapshot.sleepIntelligenceBand.isEmpty {
                    SleepIntelligencePage(snapshot: snapshot)
                }
                RecoveryPage(snapshot: snapshot)
                SleepPage(snapshot: snapshot)
                MorePage(snapshot: snapshot)
            } else {
                WaitingPage(isActivated: link.isActivated)
            }
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(Theme.watchBackground, for: .tabView)
        // A long-press rather than a fifth page or a toolbar button: the four
        // pages above are deliberately "check every glance" content (see the
        // doc comment above), and logging is the opposite -- rare, deliberate,
        // and not something that should cost a page in the every-glance swipe.
        .onLongPressGesture {
            WKInterfaceDevice.current().play(.click)
            showsQuickLog = true
        }
        .sheet(isPresented: $showsQuickLog) {
            QuickLogView()
        }
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

    private static func feelingLabel(_ rawValue: Int) -> String {
        switch rawValue {
        case 1: "Terrible"
        case 2: "Poor"
        case 3: "Okay"
        case 4: "Good"
        default: "Great"
        }
    }

    private static func feelingSymbol(_ rawValue: Int) -> String {
        switch rawValue {
        case 1: "face.dashed"
        case 2: "cloud.rain"
        case 3: "minus.circle"
        case 4: "sun.min"
        default: "sun.max"
        }
    }
}

/// Sleep Intelligence: "how did I sleep", the same question the phone's
/// hero now leads with.
struct SleepIntelligencePage: View {

    let snapshot: SleepSnapshot

    private var tint: Color {
        switch snapshot.sleepIntelligencePercent {
        case 80...: Theme.Metric.recoveryHigh
        case 60..<80: Theme.Metric.battery
        case 40..<60: Theme.Metric.recoveryMid
        default: Theme.Metric.recoveryLow
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: Double(snapshot.sleepIntelligencePercent) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.5), radius: 5)

                VStack(spacing: -3) {
                    Text("\(snapshot.sleepIntelligencePercent)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("SLEEP")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)

            Text(snapshot.sleepIntelligenceBand)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if snapshot.isMock {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }
}

/// Recovery: the one number worth showing first.
struct RecoveryPage: View {

    let snapshot: SleepSnapshot

    private var tint: Color {
        switch snapshot.recoveryPercent {
        case 67...: Theme.Metric.recoveryHigh
        case 34..<67: Theme.Metric.recoveryMid
        default: Theme.Metric.recoveryLow
        }
    }

    var body: some View {
        VStack(spacing: 6) {
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
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("RECOVERY")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                miniStat("\(snapshot.bodyBattery)", "energy", Theme.Metric.battery)
                miniStat(String(format: "%.1f", snapshot.strain), "load", Theme.Metric.strain)
            }

            if snapshot.isMock {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    private func miniStat(_ value: String, _ label: String, _ colour: Color) -> some View {
        VStack(spacing: -1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colour)
            Text(label)
                .font(Theme.text(9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Last night, and what it left you owing.
struct SleepPage: View {

    let snapshot: SleepSnapshot

    private var debtTint: Color {
        snapshot.sleepDebtMinutes <= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Last night", systemImage: "moon.stars.fill")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Metric.sleep)

            Text(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()

            // The score as a bar rather than a second big number: two large
            // numerals on one small screen and neither gets read.
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Score")
                    Spacer()
                    Text("\(snapshot.score)").monospacedDigit()
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(Theme.Metric.sleep)
                            .frame(width: geometry.size.width * Double(snapshot.score) / 100)
                    }
                }
                .frame(height: 6)
            }

            Divider().overlay(Color.white.opacity(0.15))

            HStack {
                Text("Sleep bank")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.balanceLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(debtTint)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Body Signals and Badges, stacked on one page rather than two -- both are
/// "check occasionally" information (whether anything is drifting from
/// baseline; how the reward progress is going), not "check every glance"
/// like the three pages before it, so they share a swipe instead of each
/// claiming a full screen. Body Battery itself doesn't need a page here:
/// it's already legible as a mini-stat on the Recovery page.
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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(snapshot.badgesUnlocked) of \(snapshot.badgesTotal)")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if snapshot.isMock {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
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
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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

#Preview("Sleep Intelligence") {
    SleepIntelligencePage(snapshot: MockData.snapshotWithBadges)
}

#Preview("Recovery") {
    RecoveryPage(snapshot: MockData.snapshotWithBadges)
}

#Preview("Sleep") {
    SleepPage(snapshot: MockData.snapshotWithBadges)
}

#Preview("More") {
    MorePage(snapshot: MockData.snapshotWithBadges)
}

#Preview("Waiting") {
    WaitingPage(isActivated: true)
}

#Preview("Quick Log") {
    QuickLogView()
        .environment(WatchLink())
}
