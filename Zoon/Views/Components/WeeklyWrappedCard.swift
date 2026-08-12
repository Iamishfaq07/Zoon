import SwiftUI

/// The shareable image version of the weekly report -- everything else in the
/// app is built to be read on-screen, and nothing produces something worth
/// sending to someone else. This is that: a fixed-size, self-contained card
/// rendered off-screen and exported as a PNG.
///
/// Deliberately narrower in scope than `ReportView` -- a share card that tries
/// to fit everything ends up unreadable at thumbnail size in a Messages
/// thread. Four numbers and a headline is the whole card.
struct WeeklyWrappedCard: View {

    let report: WeeklyReport

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.14), Color(red: 0.1, green: 0.08, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                recoveryHero
                Spacer(minLength: 20)
                statsGrid
                Spacer(minLength: 20)
                if let best = report.bestNight {
                    bestNightRow(best)
                }
                Spacer()
                footer
            }
            .padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("MY WEEK IN SLEEP")
                .font(Theme.label(12, weight: .heavy))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.6))
            Text("\(report.periodStart, format: .dateTime.month(.abbreviated).day()) - \(report.periodEnd, format: .dateTime.month(.abbreviated).day())")
                .font(Theme.text(12))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var recoveryHero: some View {
        if let recovery = report.averageRecovery {
            VStack(spacing: 2) {
                Text("\(Int(recovery))")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.recoveryColor(recovery))
                Text("AVERAGE RECOVERY")
                    .font(Theme.label(12, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            Text("Building your baseline")
                .font(Theme.label(16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            wrappedStat(
                value: report.averageSleepMinutes.map { SleepNightFeatures.formatMinutes($0) } ?? "--",
                label: "Avg Sleep"
            )
            divider
            wrappedStat(value: "\(report.goalHitCount)/\(report.nightCount)", label: "Goal Nights")
            divider
            wrappedStat(
                value: report.averageHRV.map { "\(Int($0))" } ?? "--",
                label: "Avg HRV"
            )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 40)
    }

    private func wrappedStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.numeral(22))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(Theme.text(10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func bestNightRow(_ night: SleepNightFeatures) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(Theme.text(13))
                .foregroundStyle(Theme.Metric.recoveryHigh)
            VStack(alignment: .leading, spacing: 1) {
                Text("Best night: \(night.date.formatted(.dateTime.weekday(.wide)))")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(night.formattedTimeAsleep) asleep, \(Int(night.sleepEfficiencyPercent))% efficient")
                    .font(Theme.text(10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "moon.stars.fill")
                .font(Theme.text(11))
            Text("Zoon")
                .font(Theme.label(12, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.4))
    }
}

/// Renders the card off-screen and hands back a temp-file URL ready for
/// `ShareLink` -- `ImageRenderer` needs the view actually laid out, which a
/// plain function can't do, so this is a tiny host view instead.
@MainActor
enum WeeklyWrappedExporter {
    static func export(_ report: WeeklyReport) -> URL? {
        let renderer = ImageRenderer(content: WeeklyWrappedCard(report: report))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return nil }
        return try? DataExporter.writeTemporary(
            data, filename: "zoon-week-\(ISO8601DateFormatter.dayOnly.string(from: report.periodEnd)).png"
        )
    }
}

#Preview("Weekly Wrapped", traits: .sizeThatFitsLayout) {
    let nights = MockData.recentWeek
    let recoveries = Dictionary(uniqueKeysWithValues: nights.map { ($0.date, Int.random(in: 55...92)) })
    let report = WeeklyReport.build(
        nights: nights, recoveries: recoveries,
        previousNights: [], previousRecoveries: [:],
        goalMinutes: 480, consistencyMinutes: 22
    )
    return WeeklyWrappedCard(report: report)
}
