import SwiftUI
import Charts

struct ChartBuilderView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @State private var prompt = "show sleep duration for the last 30 days"
    @State private var request = ChartRequest(metric: .sleepDuration)
    @State private var error: String?

    private var points: [(date: Date, value: Double)] {
        coordinator.recentNights.suffix(request.days).compactMap { night in
            let value: Double?
            switch request.metric {
            case .sleepDuration: value = night.timeAsleepMinutes / 60
            case .efficiency: value = night.sleepEfficiencyPercent
            case .hrv: value = night.avgHRV
            case .bedtime:
                let c = Calendar.current.dateComponents([.hour, .minute], from: night.bedtime)
                value = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }
            return value.map { (night.date, $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ask for a chart").font(.title2.bold())
                Text("Type a metric and time range. Calculations run locally from your stored nights.").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                HStack { TextField("e.g. HRV last 90 days weekly", text: $prompt, axis: .vertical).textFieldStyle(.roundedBorder); Button("Build") { build() }.buttonStyle(.borderedProminent) }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("\(request.metric.label) · last \(request.days) days\(request.groupedWeekly ? " · weekly view" : "")").font(.headline)
                Chart {
                    ForEach(points, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value(request.metric.label, point.value)).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date), y: .value(request.metric.label, point.value)).symbolSize(18)
                    }
                }.frame(height: 240).glassCard()
                Text("No causes are inferred from this chart. It is a transparent view of the values Zoon has available.").font(.caption).foregroundStyle(Theme.inkSecondary)
            }.padding()
        }.nightBackground().navigationTitle("Chart builder").navigationBarTitleDisplayMode(.inline)
    }
    private func build() { if let parsed = ChartRequestParser.parse(prompt) { request = parsed; error = nil } else { error = "Try “sleep duration”, “efficiency”, “HRV”, or “bedtime” with a day range." } }
}
