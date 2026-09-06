import SwiftUI

struct ScoreLightSnapshotView: View {
    let snapshot: SleepSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Sleep", systemImage: "moon.fill").font(.caption)
            Text(SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes))
                .font(.headline).minimumScaleFactor(0.7)
            Text(snapshot.date, style: .date).font(.caption2).foregroundStyle(.secondary)
        }.privacySensitive()
    }
}
