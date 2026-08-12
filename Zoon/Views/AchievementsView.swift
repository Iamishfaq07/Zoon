import SwiftUI

/// The badge grid.
///
/// Locked badges are shown with their real progress rather than as silhouettes.
/// A grid of question marks is a grid of things you have failed to do; a grid of
/// part-filled rings is a map.
struct AchievementsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps

    @State private var selected: Achievement?

    private var achievements: [Achievement] {
        AchievementEngine.evaluate(
            nights: coordinator.recentNights,
            goalMinutes: preferences.sleepGoalMinutes,
            journalTaggedNights: coordinator.journal.taggedNightCount(),
            napCount: naps.naps.count,
            // Same reasoning as DayContextBuilder: `.index` is a hardcoded 0
            // below SleepRegularity.minimumNights, not a real "zero
            // regularity" reading, so it must not reach the badge engine
            // until `hasEnoughData` says the number means something.
            regularityIndex: coordinator.state.context?.regularity.hasEnoughData == true
                ? coordinator.state.context?.regularity.index
                : nil
        )
    }

    private var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                summary.entrance(0)

                ForEach(Array(Achievement.Category.allCases.enumerated()), id: \.element) { index, category in
                    let items = achievements.filter { $0.category == category }
                    if !items.isEmpty {
                        section(category, items).entrance(index + 1)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { achievement in
            AchievementDetailSheet(achievement: achievement)
                .presentationDetents([.height(340)])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.neutral(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(unlockedCount) / Double(max(1, achievements.count)))
                    .stroke(
                        AngularGradient(
                            colors: [Theme.Metric.sleep, Theme.Metric.battery, Theme.Metric.recoveryMid],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.value, value: unlockedCount)

                VStack(spacing: -1) {
                    Text("\(unlockedCount)")
                        .font(Theme.numeral(30))
                        .monospacedDigit()
                    Text("of \(achievements.count)")
                        .font(Theme.text(10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 108, height: 108)

            if let next = AchievementEngine.nextUp(achievements) {
                VStack(spacing: 3) {
                    Text("Closest: \(next.title)")
                        .font(Theme.label(13, weight: .semibold))
                    Text(next.progressText)
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text("Badges are never taken away. Nothing here depends on an unbroken run — a sleep app that punishes one bad night is working against you.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    // MARK: - Sections

    private func section(_ category: Achievement.Category, _ items: [Achievement]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: category.label, systemImage: symbol(for: category))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 12)],
                spacing: 12
            ) {
                ForEach(items) { achievement in
                    Button {
                        Haptics.tap()
                        selected = achievement
                    } label: {
                        BadgeTile(achievement: achievement)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .glassCard()
    }

    private func symbol(for category: Achievement.Category) -> String {
        switch category {
        case .duration: "clock.fill"
        case .consistency: "repeat"
        case .quality: "sparkles"
        case .recovery: "heart.fill"
        case .habits: "hand.raised.fill"
        }
    }
}

/// A single badge.
///
/// The hexagon is deliberate. Circles are already spoken for in this app —
/// recovery, strain, body battery, body clock are all rings — so a badge drawn
/// as one more ring would read as another metric. A hexagon says "award"
/// without a label having to.
struct BadgeTile: View {

    let achievement: Achievement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var tint: Color {
        switch achievement.tier {
        case .bronze: Color(red: 0.80, green: 0.53, blue: 0.32)
        case .silver: Color(red: 0.76, green: 0.80, blue: 0.87)
        case .gold: Color(red: 1.00, green: 0.78, blue: 0.31)
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Hexagon()
                    .fill(
                        achievement.isUnlocked
                        ? LinearGradient(
                            colors: [tint.opacity(0.85), tint.opacity(0.35)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Theme.neutral(0.07), Theme.neutral(0.03)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Hexagon().strokeBorder(
                            achievement.isUnlocked ? tint : Theme.neutral(0.12),
                            lineWidth: 1.5
                        )
                    }
                    .frame(width: 62, height: 68)
                    .shadow(
                        color: achievement.isUnlocked ? tint.opacity(0.45) : .clear,
                        radius: 10
                    )

                // Locked badges show a progress arc around the hexagon rather
                // than a padlock. The arc is the information; a padlock is just
                // a reminder that you don't have it.
                if !achievement.isUnlocked {
                    Circle()
                        .trim(from: 0, to: appeared ? achievement.progress : 0)
                        .stroke(
                            tint.opacity(0.75),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 76, height: 76)
                }

                Image(systemName: achievement.symbol)
                    .font(Theme.text(22, weight: .medium))
                    .foregroundStyle(achievement.isUnlocked ? .black : .secondary)
            }
            .frame(height: 80)

            Text(achievement.title)
                .font(Theme.label(11, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 26, alignment: .top)
                .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)

            if !achievement.isUnlocked {
                Text(achievement.progressText)
                    .font(Theme.text(9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(Motion.value.delay(0.15)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievement.title)
        .accessibilityValue(
            achievement.isUnlocked
            ? "Earned. \(achievement.detail)"
            : "\(achievement.progressText). \(achievement.detail)"
        )
    }
}

/// Flat-top hexagon, drawn to fit its rect.
struct Hexagon: InsettableShape {

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = r.width, h = r.height
        // Corners at 1/4 and 3/4 height — the proportions of a shield rather
        // than a regular hexagon, which reads better at tile size.
        var path = Path()
        path.move(to: CGPoint(x: r.minX + w / 2, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.25))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.75))
        path.addLine(to: CGPoint(x: r.minX + w / 2, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.75))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.25))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Hexagon {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Tapping a badge explains it. Locked ones especially — that's the whole
/// reason the grid is tappable.
struct AchievementDetailSheet: View {

    let achievement: Achievement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            BadgeTile(achievement: achievement)
                .scaleEffect(1.35)
                .padding(.top, 30)

            VStack(spacing: 8) {
                Text(achievement.title)
                    .font(Theme.numeral(22))
                Text(achievement.detail)
                    .font(Theme.text(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            if achievement.isUnlocked {
                StatusPill(text: "\(achievement.tier.label) · Earned", systemImage: "checkmark.seal.fill", tint: Theme.Metric.recoveryHigh)
            } else {
                VStack(spacing: 6) {
                    ProgressView(value: achievement.progress)
                        .tint(Theme.Metric.sleep)
                        .frame(width: 190)
                    Text(achievement.progressText)
                        .font(Theme.text(12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .presentationDragIndicator(.visible)
    }
}

#Preview("Badges") {
    NavigationStack {
        AchievementsView().zoonPreviewEnvironment()
    }
}

#Preview("Tiles") {
    let items = AchievementEngine.evaluate(nights: MockData.history, goalMinutes: 420)
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
            ForEach(items) { BadgeTile(achievement: $0) }
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
