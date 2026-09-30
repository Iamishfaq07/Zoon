import SwiftUI

/// Where resting heart rate, HRV and cardio fitness sit against people of
/// the same age and sex.
///
/// Sits under "Long-term baselines" on Insights, which answers "am I
/// changing?" against the person's own history. This answers the question
/// that view cannot: "is my number unusual for someone like me?" See
/// `HeartContext` for the sources and why none of this feeds a score.
struct ForYourAgeCard: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    @State private var vo2Max: Double?
    @State private var isFilling = false
    @State private var fillMessage: String?

    /// Sample nights come with a sample person (see
    /// `SleepDataCoordinator.demographic`), so the demo shows the card it
    /// describes instead of a prompt to fill in a profile.
    private var isSample: Bool { coordinator.state.isMock }

    private var age: Int? { coordinator.demographic?.ageYears }

    private var sex: DemographicBaseline.Sex {
        coordinator.demographic?.sex ?? preferences.biologicalSex
    }

    /// Median of the last two weeks, and only with at least three nights:
    /// one reading is a night, not a person.
    private func recentMedian(_ value: (SleepNightFeatures) -> Double?) -> Double? {
        let values = coordinator.recentNights.suffix(14).compactMap(value)
        guard values.count >= 3 else { return nil }
        return Statistics.median(values)
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let valueText: String
        let reading: HeartContext.Reading
        let scale: ClosedRange<Double>
        let tint: Color
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let resting = recentMedian({ $0.restingHeartRate }) {
            rows.append(Row(
                id: "rhr",
                title: SleepVocabulary.restingHeartRate.plain,
                valueText: "\(Int(resting.rounded())) bpm",
                reading: HeartContext.restingHeartRate(resting, sex: sex),
                scale: 35...110,
                tint: Theme.Metric.heart
            ))
        }
        if let age, let hrv = recentMedian({ $0.avgHRV }) {
            let reading = HeartContext.heartRateVariability(hrv, age: age)
            rows.append(Row(
                id: "hrv",
                title: SleepVocabulary.hrv.full,
                valueText: "\(Int(hrv.rounded())) ms",
                reading: reading,
                scale: 0...max(100, reading.reference.upperBound * 1.4),
                tint: Theme.Metric.hrv
            ))
        }
        if let age, let vo2Max, let reading = HeartContext.cardioFitness(vo2Max, age: age, sex: sex) {
            rows.append(Row(
                id: "vo2",
                title: SleepVocabulary.cardioFitness.full,
                valueText: String(format: "%.1f", vo2Max),
                reading: reading,
                scale: (reading.reference.lowerBound * 0.55)...(reading.reference.upperBound * 1.45),
                tint: Theme.Metric.strain
            ))
        }
        return rows
    }

    private var subtitle: String {
        guard let age else {
            return "Add your age to compare with people like you."
        }
        switch sex {
        case .female: return "Compared with women aged about \(age)."
        case .male: return "Compared with men aged about \(age)."
        case .unspecified: return "Compared with adults aged about \(age). Add your sex for a closer match."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionHeader(title: "For your age", subtitle: subtitle, systemImage: "person.crop.circle.badge.checkmark")
                if isSample {
                    StatusPill(text: "Sample", systemImage: "wand.and.stars", tint: Theme.inkSecondary)
                }
            }

            if rows.isEmpty {
                Text("Wear your watch to bed for a few nights and your resting heart rate and HRV will appear here.")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(rows) { row in
                rowView(row)
                if row.id != rows.last?.id {
                    Rectangle().fill(Theme.cardStroke).frame(height: 1)
                }
            }

            if age == nil || sex == .unspecified {
                profilePrompt
            }

            Text("Ranges from published studies of healthy adults. Your own trend matters more than where you sit in a crowd.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
        .task(id: coordinator.lastRefresh) {
            vo2Max = await coordinator.latestVO2Max()
        }
    }

    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(Theme.label(14, weight: .semibold))
                Spacer(minLength: 8)
                Text(row.valueText)
                    .font(Theme.label(16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(row.tint)
            }
            PopulationRangeBar(
                scale: row.scale,
                band: row.reading.reference,
                value: row.reading.value,
                tint: row.tint
            )
            HStack(spacing: 6) {
                positionChip(row.reading)
                Spacer(minLength: 0)
            }
            Text(row.reading.sentence)
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.valueText). \(row.reading.position.label). \(row.reading.sentence)")
    }

    /// Neutral wording and colour: sitting below or above a population
    /// middle is information, not an alarm.
    private func positionChip(_ reading: HeartContext.Reading) -> some View {
        let favourable: Bool? = switch reading.position {
        case .typical: nil
        case .above: reading.higherIsFavourable
        case .below: !reading.higherIsFavourable
        }
        let tint: Color = switch favourable {
        case true: Theme.Metric.recoveryHigh
        case false: Theme.Family.attention
        case nil: Theme.Metric.sleep
        }
        return Text(reading.position.label)
            .font(Theme.label(11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var profilePrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            if DataEnvironment.current.isLive && HealthKitManager.isHealthDataAvailable {
                Button {
                    Task { await fillFromHealth() }
                } label: {
                    HStack(spacing: 8) {
                        if isFilling {
                            ProgressView()
                        } else {
                            Image(systemName: "heart.text.square.fill")
                        }
                        Text("Use my age and sex from Health")
                    }
                    .font(Theme.label(14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Metric.sleep)
                .disabled(isFilling)
            }
            Text(fillMessage ?? "Or set them in Settings, under You. They stay on this iPhone.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fillFromHealth() async {
        isFilling = true
        defer { isFilling = false }
        let profile = await coordinator.fillProfileFromHealth(requestingAccess: true, onlyMissing: false)
        fillMessage = Self.fillSummary(profile)
        Haptics.success()
    }

    /// What the fill did, in a sentence.
    static func fillSummary(_ profile: HealthProfile) -> String {
        var filled: [String] = []
        if profile.age != nil { filled.append("age") }
        if profile.sex != nil { filled.append("sex") }
        if profile.bodyMassIndex != nil { filled.append("BMI") }
        guard !filled.isEmpty else {
            return "Health did not share an age or sex. You can set them in Settings, under You."
        }
        return "Filled your \(ListFormatter.localizedString(byJoining: filled)) from Health."
    }
}

/// A horizontal track with the population band shaded and the person's
/// value as a dot. The dot slides in from the left on first appearance.
struct PopulationRangeBar: View {
    let scale: ClosedRange<Double>
    let band: ClosedRange<Double>
    let value: Double
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = max(scale.upperBound - scale.lowerBound, 0.001)
            let x: (Double) -> CGFloat = { raw in
                let clamped = min(max(raw, scale.lowerBound), scale.upperBound)
                return CGFloat((clamped - scale.lowerBound) / span) * width
            }
            let bandStart = x(band.lowerBound)
            let bandWidth = max(8, x(band.upperBound) - bandStart)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.neutral(0.10))
                    .frame(height: 8)
                Capsule()
                    .fill(tint.opacity(0.30))
                    .frame(width: bandWidth, height: 8)
                    .offset(x: bandStart)
                Circle()
                    .fill(tint)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2.5))
                    .frame(width: 16, height: 16)
                    .shadow(color: tint.opacity(0.55), radius: 5)
                    .offset(x: (appeared ? x(value) : 0) - 8)
            }
            .frame(width: width, height: 16)
        }
        .frame(height: 16)
        // A number line reads low to high left to right in every language;
        // the offsets above assume it.
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            guard !appeared else { return }
            withAnimation(Motion.respecting(reduceMotion, Motion.hero)) {
                appeared = true
            }
            if reduceMotion { appeared = true }
        }
        .accessibilityHidden(true)
    }
}
