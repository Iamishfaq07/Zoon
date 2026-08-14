import SwiftUI

/// One night's meaningful events, told as a chronological timeline rather
/// than a score. See `SleepStory`'s own doc comment for why this exists
/// separately from every other, score-first screen in the app.
struct SleepStoryView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    @State private var selectedDate: Date?

    private var recentNights: [SleepNightFeatures] {
        Array(coordinator.recentNights.suffix(14)).sorted { $0.date > $1.date }
    }

    private var selectedNight: SleepNightFeatures? {
        guard let selectedDate else { return recentNights.first }
        return recentNights.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) } ?? recentNights.first
    }

    private var story: SleepStory? {
        guard let night = selectedNight else { return nil }
        let tagLabels = coordinator.journal.entry(for: night.date)?.tags.map(\.label) ?? []
        return SleepStory.build(night: night, tagLabels: tagLabels)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                if recentNights.isEmpty {
                    ContentUnavailableView("No nights yet", systemImage: "moon.zzz")
                        .padding(.top, 60)
                } else {
                    nightPicker
                    if let story {
                        timelineCard(story)
                    }
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Sleep Story")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var nightPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentNights) { night in
                    dayChip(night)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func dayChip(_ night: SleepNightFeatures) -> some View {
        let isSelected = Calendar.current.isDate(night.date, inSameDayAs: selectedNight?.date ?? night.date)
        return Button {
            selectedDate = night.date
        } label: {
            VStack(spacing: 3) {
                Text(night.date, format: .dateTime.weekday(.abbreviated))
                    .font(Theme.text(10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(night.date, format: .dateTime.day())
                    .font(Theme.label(16, weight: .bold))
            }
            .frame(width: 46, height: 50)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.Metric.sleep.opacity(0.25) : Theme.neutral(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Theme.Metric.sleep : Theme.cardStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func timelineCard(_ story: SleepStory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "What happened",
                subtitle: "In the order it happened -- nothing here claims one event caused the next.",
                systemImage: "clock.arrow.circlepath"
            )
            .padding(.bottom, 14)

            ForEach(Array(story.events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: event.symbol)
                            .font(Theme.text(11, weight: .medium))
                            .foregroundStyle(Theme.Metric.sleep)
                            .frame(width: 26, height: 26)
                            .background(Theme.Metric.sleep.opacity(0.15), in: Circle())
                        if index < story.events.count - 1 {
                            Rectangle()
                                .fill(Theme.cardStroke)
                                .frame(width: 1)
                                .frame(minHeight: 20)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.title)
                                .font(Theme.label(13, weight: .semibold))
                            Spacer()
                            Text(event.time, format: .dateTime.hour().minute())
                                .font(Theme.text(11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        if let detail = event.detail {
                            Text(detail)
                                .font(Theme.text(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, index < story.events.count - 1 ? 14 : 0)
                }
            }
        }
        .glassCard()
    }
}

#Preview("Sleep Story") {
    NavigationStack { SleepStoryView() }
        .zoonPreviewEnvironment()
}
