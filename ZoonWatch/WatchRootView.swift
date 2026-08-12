import SwiftUI

/// Three pages, swiped horizontally.
///
/// A `TabView` in page style rather than a list: on a watch, swiping between
/// full-bleed screens is faster than scrolling a list and tapping into detail,
/// and each page is sized to be legible without the wrist being still.
struct WatchRootView: View {

    @Environment(WatchLink.self) private var link

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
                BatteryPage(snapshot: snapshot)
                BadgePage(snapshot: snapshot)
            } else {
                WaitingPage(isActivated: link.isActivated)
            }
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(Theme.watchBackground, for: .tabView)
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

/// Body Battery on its own page — it was previously only a mini-stat on the
/// Recovery page, too small to read the exact number without stopping to
/// squint. A dedicated ring gives it the same legibility as Recovery gets.
struct BatteryPage: View {

    let snapshot: SleepSnapshot

    private var tint: Color {
        switch snapshot.bodyBattery {
        case 60...: Theme.Metric.recoveryHigh
        case 30..<60: Theme.Metric.battery
        default: Theme.Metric.recoveryLow
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: Double(snapshot.bodyBattery) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.5), radius: 5)

                VStack(spacing: -3) {
                    Text("\(snapshot.bodyBattery)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("ENERGY")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)

            if snapshot.isMock {
                Text("Sample data")
                    .font(Theme.text(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }
}

/// Badges, so the wrist carries the reward too.
struct BadgePage: View {

    let snapshot: SleepSnapshot

    private var hasBadge: Bool { !snapshot.badgeTitle.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasBadge ? snapshot.badgeSymbol : "hexagon")
                .font(Theme.text(30, weight: .medium))
                .foregroundStyle(hasBadge ? Theme.Metric.recoveryMid : .secondary)

            Text(hasBadge ? snapshot.badgeTitle : "No badges yet")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(snapshot.badgesUnlocked) of \(snapshot.badgesTotal)")
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if !snapshot.nextBadgeTitle.isEmpty {
                Divider().overlay(Color.white.opacity(0.15))
                VStack(spacing: 3) {
                    Text("Next: \(snapshot.nextBadgeTitle)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: snapshot.nextBadgeProgress)
                        .tint(Theme.Metric.recoveryMid)
                }
            }
        }
        .padding(.horizontal, 8)
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

#Preview("Battery") {
    BatteryPage(snapshot: MockData.snapshotWithBadges)
}

#Preview("Badges") {
    BadgePage(snapshot: MockData.snapshotWithBadges)
}

#Preview("Waiting") {
    WaitingPage(isActivated: true)
}
