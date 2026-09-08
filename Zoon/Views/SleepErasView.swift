import SwiftUI

struct SleepErasView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sleep eras").font(.title2.bold())
                Text("A timeline of stable stretches in your history. Zoon reports timing and duration shifts without guessing why they happened.")
                    .font(.subheadline).foregroundStyle(.secondary)
                let eras = SleepEras.detect(in: Array(coordinator.recentNights.suffix(365)))
                if eras.isEmpty {
                    ZoonEmptyState(kind: .learning(collected: coordinator.recentNights.count, typicallyNeeded: 7...14, message: "A few more weeks of sleep history will reveal stable eras."))
                } else {
                    ForEach(eras) { era in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(era.start.formatted(date: .abbreviated, time: .omitted)).font(.headline); Spacer(); Text("\(era.nights) nights").font(.caption).foregroundStyle(.secondary) }
                            Text("Through \(era.end.formatted(date: .abbreviated, time: .omitted)) · average \(Int(era.averageSleepMinutes / 60))h \(Int(era.averageSleepMinutes.truncatingRemainder(dividingBy: 60)))m")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let shift = era.timingShiftMinutes, abs(shift) >= 10 { Label("Timing shifted \(abs(shift)) min \(shift > 0 ? "later" : "earlier")", systemImage: "clock.arrow.2.circlepath") }
                            if let shift = era.durationShiftMinutes, abs(shift) >= 10 { Label("Average sleep changed \(abs(shift)) min", systemImage: "moon.zzz.fill") }
                        }.glassCard()
                    }
                }
            }.padding()
        }.nightBackground().navigationTitle("Sleep eras").navigationBarTitleDisplayMode(.inline)
    }
}
