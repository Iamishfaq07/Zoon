import SwiftUI

struct SleepFingerprintView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @State private var days = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sleep fingerprint").font(.title2.bold())
                Text("A calm summary of what your sleep usually looks like. It describes patterns; it does not diagnose causes.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Period", selection: $days) {
                    Text("7 nights").tag(7); Text("30 nights").tag(30); Text("90 nights").tag(90)
                }.pickerStyle(.segmented)
                if let fingerprint = SleepFingerprint.make(from: coordinator.recentNights, days: days) {
                    FingerprintRings(fingerprint: fingerprint)
                    VStack(alignment: .leading, spacing: 12) {
                        metric("Timing", fingerprint.timingStability, "How consistently your sleep starts")
                        metric("Duration", fingerprint.durationStability, "How much your sleep length varies")
                        metric("Continuity", fingerprint.continuity, "How uninterrupted your sleep tends to be")
                        metric("Body signals", fingerprint.bodySignalStability, "How steady your available HRV readings are")
                    }.glassCard()
                    Text("Based on \(fingerprint.sampleCount) recent nights. Missing sensors simply reduce the body-signal score.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ZoonEmptyState(kind: .learning(collected: coordinator.recentNights.count, typicallyNeeded: 3...7, message: "Keep logging sleep for a few more nights to reveal your fingerprint."))
                }
            }.padding()
        }.nightBackground().navigationTitle("Sleep fingerprint").navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ title: String, _ value: Double, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.headline); Spacer(); Text("\(Int(value * 100))%").font(.headline.monospacedDigit()) }
            ProgressView(value: value).tint(Theme.Family.sleep)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FingerprintRings: View {
    let fingerprint: SleepFingerprint
    var body: some View {
        ZStack {
            Circle().stroke(Theme.Family.sleep.opacity(0.15), lineWidth: 24)
            Circle().trim(from: 0, to: fingerprint.timingStability).stroke(Theme.Family.sleep, style: StrokeStyle(lineWidth: 24, lineCap: .round)).rotationEffect(.degrees(-90))
            Circle().trim(from: 0, to: fingerprint.continuity).stroke(Theme.Family.recovery, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack { Text("Your pattern").font(.caption).foregroundStyle(.secondary); Text("\(fingerprint.sampleCount) nights").font(.title3.bold()) }
        }.frame(height: 210).frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}
