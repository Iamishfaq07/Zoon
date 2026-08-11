import SwiftUI

/// One past night, on its own — everything `SleepDetailView` shows except the
/// pieces that are inherently about *today*: strain, body battery, and
/// chronotype all compare against activity and rolling context that isn't
/// reconstructed for historical dates. Shape, stages, timing, and vitals are
/// all just stored data, so those travel unchanged.
struct PastNightDetailView: View {

    let night: SleepNightFeatures

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                headline
                hypnogramCard
                stagesCard
                timingCard
                vitalsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle(night.date.formatted(.dateTime.weekday(.wide).month().day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text(night.formattedTimeAsleep)
                .font(Theme.numeral(52))
                .monospacedDigit()
            Text("asleep")
                .font(Theme.label(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var hypnogramCard: some View {
        if !night.stageSegments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Sleep Stages",
                    subtitle: "Deep sleep clusters early; REM builds toward morning.",
                    systemImage: "chart.xyaxis.line"
                )
                HypnogramView(segments: night.stageSegments)
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private var stagesCard: some View {
        if night.hasStageBreakdown {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Stage Breakdown", systemImage: "square.stack.3d.up")
                StageProportionBar(features: night)
                StageLegend(features: night)
            }
            .glassCard()
        }
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Timing & Quality", systemImage: "clock")

            row("Bedtime", night.bedtime.formatted(.dateTime.hour().minute()))
            row("Wake time", night.wakeTime.formatted(.dateTime.hour().minute()))
            row("Time in bed", SleepNightFeatures.formatMinutes(night.timeInBedMinutes))
            row("Efficiency", "\(Int(night.sleepEfficiencyPercent))%")
            if let latency = night.sleepLatencyMinutes {
                row("Fell asleep in", "\(Int(latency)) min")
            }
            row("Awakenings", "\(night.wakeCount)")
        }
        .glassCard()
    }

    @ViewBuilder
    private var vitalsCard: some View {
        // Plain values, deliberately not run through `VitalsStatus` -- that
        // comparison needs a rolling baseline computed the same way today's
        // context is, which isn't reconstructed per historical date here.
        let rows = vitalRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Vitals", systemImage: "waveform.path.ecg")
                ForEach(rows, id: \.label) { entry in
                    row(entry.label, entry.value)
                }
            }
            .glassCard()
        }
    }

    private var vitalRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let hr = night.avgHeartRate {
            rows.append(("Heart rate", "\(Int(hr.rounded())) bpm"))
        }
        if let hrv = night.avgHRV {
            rows.append(("HRV", "\(Int(hrv.rounded())) ms"))
        }
        if let resp = night.avgRespiratoryRate {
            rows.append(("Respiratory rate", String(format: "%.1f br/min", resp)))
        }
        if let spo2 = night.avgSpO2 {
            rows.append(("Blood oxygen", "\(Int(spo2.rounded()))%"))
        }
        if let temp = night.wristTempDeltaC {
            let sign = temp >= 0 ? "+" : ""
            rows.append(("Wrist temperature", String(format: "%@%.1f°C vs usual", sign, temp)))
        }
        if let disturbances = night.breathingDisturbances {
            rows.append(("Breathing disturbances", "\(Int(disturbances.rounded()))% of night"))
        }
        return rows
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.label(12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.label(13, weight: .semibold))
                .monospacedDigit()
        }
    }
}

#Preview("Past Night") {
    NavigationStack {
        PastNightDetailView(night: AppMockData.dayContext().night)
    }
    .preferredColorScheme(.dark)
}
