import SwiftUI

/// "Your month in sleep": a calendar of moons, the few numbers worth
/// remembering, and a card to share. See `MonthRecap`.
struct MonthRecapView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 is this month, 1 the one before, and so on.
    @State private var monthsBack = 0
    @State private var shareURL: URL?

    private var calendar: Calendar { .current }

    private func month(_ back: Int) -> DateInterval? {
        guard let date = calendar.date(byAdding: .month, value: -back, to: .now) else { return nil }
        return MonthRecap.calendarMonth(containing: date, calendar: calendar)
    }

    private var recap: MonthRecap? {
        guard let month = month(monthsBack) else { return nil }
        return MonthRecap.make(
            nights: coordinator.recentNights,
            goalMinutes: preferences.sleepGoalMinutes,
            month: month,
            previousMonth: self.month(monthsBack + 1),
            calendar: calendar
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                monthPicker
                if let recap {
                    content(recap)
                        .id(monthsBack)
                        .transition(.opacity)
                } else {
                    ZoonEmptyState(
                        kind: .noData(
                            title: "Not enough nights this month",
                            message: "A recap needs at least \(MonthRecap.minimumNights) nights in the month.",
                            unlocks: ["Your month in sleep", "A card to share"]
                        )
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
            .animation(Motion.respecting(reduceMotion, Motion.standard), value: monthsBack)
        }
        .nightBackground()
        .navigationTitle("Your month")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: monthsBack) {
            if let recap {
                shareURL = MonthRecapExporter.export(recap)
            } else {
                shareURL = nil
            }
        }
    }

    private var monthPicker: some View {
        HStack {
            Button {
                monthsBack += 1
                Haptics.select()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(monthsBack >= 11)
            .accessibilityLabel("Previous month")
            Spacer()
            Text(month(monthsBack)?.start.formatted(.dateTime.month(.wide).year()) ?? "")
                .font(Theme.label(17, weight: .semibold))
            Spacer()
            Button {
                monthsBack -= 1
                Haptics.select()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(monthsBack == 0)
            .accessibilityLabel("Next month")
        }
    }

    @ViewBuilder
    private func content(_ recap: MonthRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(recap.headline)
                .font(Theme.heading(24))
                .fixedSize(horizontal: false, vertical: true)
            MonthMoonGrid(recap: recap)
            Text("Each moon fills with how much of your \(SleepNightFeatures.formatMinutes(recap.goalMinutes)) goal that night reached.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            stat("A night, on average", SleepNightFeatures.formatMinutes(recap.averageAsleepMinutes), tint: Theme.Metric.sleep)
            stat("Nights at goal", "\(recap.goalNights) of \(recap.nightCount)", tint: Theme.Metric.recoveryHigh)
            stat("Longest run at goal", recap.longestGoalStreak == 1 ? "1 night" : "\(recap.longestGoalStreak) nights", tint: Theme.Metric.battery)
            if let bedtime = recap.typicalBedtimeMinutes {
                stat(
                    "Usual bedtime",
                    Self.clock(bedtime),
                    tint: Theme.Family.circadian,
                    note: recap.bedtimeSpreadMinutes.map { "give or take \(Int($0.rounded())) min" }
                )
            }
            if let deep = recap.averageDeepPercent {
                stat("Deep sleep", "\(Int(deep.rounded()))%", tint: Theme.Stage.color(for: .deep))
            }
            if let change = recap.changeFromPreviousMinutes {
                stat(
                    "Against last month",
                    (change >= 0 ? "+" : "−") + SleepNightFeatures.formatMinutes(abs(change)),
                    tint: change >= 0 ? Theme.Metric.recoveryHigh : Theme.Family.attention,
                    note: "a night"
                )
            }
        }

        if let best = recap.bestNight {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.Metric.recoveryMid)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best night: \(best.dayString())")
                        .font(Theme.label(15, weight: .semibold))
                    Text("\(best.formattedTimeAsleep) asleep, \(Int(best.sleepEfficiencyPercent))% of the time in bed")
                        .font(Theme.text(14))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .glassCard()
            .accessibilityElement(children: .combine)
        }

        if let shareURL {
            ShareLink(
                item: shareURL,
                preview: SharePreview("My month in sleep", image: Image(systemName: "moon.stars.fill"))
            ) {
                Label("Share my month", systemImage: "square.and.arrow.up")
                    .font(Theme.label(15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.Metric.sleep.opacity(0.25), in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func stat(_ label: String, _ value: String, tint: Color, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.label(13, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(value)
                .font(Theme.heading(24))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let note {
                Text(note)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    /// Minutes after midnight as a clock time on this device.
    static func clock(_ minutes: Double) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        return start.addingTimeInterval(minutes * 60).formatted(date: .omitted, time: .shortened)
    }
}

/// The month as a calendar of moons, Monday or Sunday first as the device
/// prefers.
struct MonthMoonGrid: View {
    let recap: MonthRecap
    var moonSize: CGFloat = 30
    var textColor: Color = Theme.inkTertiary

    private var leadingBlanks: Int {
        let calendar = Calendar.current
        guard let first = recap.days.first else { return 0 }
        let weekday = calendar.component(.weekday, from: first.date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: moonSize)
            }
            ForEach(recap.days) { day in
                VStack(spacing: 2) {
                    if let asleep = day.asleepMinutes {
                        MoonFill(
                            fill: min(1, asleep / max(recap.goalMinutes, 1)),
                            active: asleep >= recap.goalMinutes,
                            size: moonSize
                        )
                    } else {
                        Circle()
                            .stroke(textColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            .frame(width: moonSize * 0.7, height: moonSize * 0.7)
                            .frame(height: moonSize)
                    }
                    Text(day.date, format: .dateTime.day())
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(textColor)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(recap.goalNights) of \(recap.nightCount) recorded nights reached the goal")
    }
}

/// The shareable card: a portrait image, dark, readable at thumbnail size.
struct MonthRecapShareCard: View {
    let recap: MonthRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MY MONTH IN SLEEP")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(recap.month.start.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(recap.headline)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            MonthMoonGrid(recap: recap, moonSize: 34, textColor: .white.opacity(0.5))
            HStack(spacing: 0) {
                cell(SleepNightFeatures.formatMinutes(recap.averageAsleepMinutes), "a night")
                cell("\(recap.goalNights)/\(recap.nightCount)", "at goal")
                cell("\(recap.longestGoalStreak)", "best run")
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "moon.stars.fill")
                Text("Zoon")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.45))
        }
        .padding(32)
        .frame(width: 400, height: 710, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.14), Color(red: 0.13, green: 0.09, blue: 0.27)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .environment(\.colorScheme, .dark)
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
enum MonthRecapExporter {
    static func export(_ recap: MonthRecap) -> URL? {
        let renderer = ImageRenderer(content: MonthRecapShareCard(recap: recap))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let name = "zoon-\(recap.month.start.formatted(.iso8601.year().month())).png"
        return try? DataExporter.writeTemporary(data, filename: name)
    }
}
