import SwiftUI

/// Empty, learning and error states that keep the page's shape.
///
/// The failure mode this replaces is a `ContentUnavailableView` dropped into
/// the middle of a screen that otherwise has a hero, a strip and a timeline:
/// the layout collapses to an icon and two lines, and the person has no
/// sense of what the screen *will* look like once there's data. Each state
/// here says what happened, what it affects, and what to do -- and the
/// learning state shows honest progress rather than a promised night count.
struct ZoonEmptyState: View {
    enum Kind {
        /// Nothing measured yet. A resting moon, and what will unlock.
        case noData(title: String, message: String, unlocks: [String])
        /// Some nights collected, not yet enough to say anything.
        case learning(collected: Int, typicallyNeeded: ClosedRange<Int>, message: String)
        /// A sensor this device doesn't have or hasn't reported yet.
        case missingSensor(name: String, message: String)
        /// Something went wrong reading data.
        case failed(title: String, message: String)
    }

    let kind: Kind
    var primaryAction: (label: String, action: () -> Void)?
    var secondaryAction: (label: String, action: () -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        VStack(spacing: 18) {
            glyph
                .frame(width: 96, height: 96)
                .opacity(settled ? 1 : 0)
                .scaleEffect(settled ? 1 : 0.96)

            VStack(spacing: 6) {
                Text(title)
                    .font(Theme.label(18, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Theme.evidence)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case let .learning(collected, needed, _) = kind {
                learningBar(collected: collected, needed: needed)
            }

            if case let .noData(_, _, unlocks) = kind, !unlocks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(unlocks, id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.dashed")
                                .font(Theme.text(11))
                                .foregroundStyle(.tertiary)
                            Text(item)
                                .font(Theme.text(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if primaryAction != nil || secondaryAction != nil {
                VStack(spacing: 8) {
                    if let primaryAction {
                        Button(primaryAction.label, action: primaryAction.action)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Family.sleep)
                    }
                    if let secondaryAction {
                        Button(secondaryAction.label, action: secondaryAction.action)
                            .buttonStyle(.plain)
                            .font(Theme.text(13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .onAppear {
            withAnimation(Motion.respecting(reduceMotion, Motion.hero)) { settled = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch kind {
        case let .noData(title, _, _): title
        case .learning: "Zoon is learning"
        case let .missingSensor(name, _): name
        case let .failed(title, _): title
        }
    }

    private var message: String {
        switch kind {
        case let .noData(_, message, _): message
        case let .learning(_, _, message): message
        case let .missingSensor(_, message): message
        case let .failed(_, message): message
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .noData, .learning:
            // A resting crescent: the orbit with nothing in it yet.
            ZStack {
                Circle().stroke(Theme.neutral(0.10), lineWidth: 6)
                Circle()
                    .trim(from: 0.62, to: 0.92)
                    .stroke(Theme.Family.sleep.opacity(0.7), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.Family.sleep)
            }
        case .missingSensor:
            ZStack {
                Circle().stroke(Theme.neutral(0.10), style: StrokeStyle(lineWidth: 4, dash: [6, 6]))
                Image(systemName: "applewatch.slash")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
            }
        case .failed:
            ZStack {
                Circle().stroke(Theme.Family.attention.opacity(0.35), lineWidth: 4)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.Family.attention)
            }
        }
    }

    /// Honest progress: filled to `collected / needed.lowerBound`, with the
    /// text stating a range rather than a single number the algorithm might
    /// not actually require.
    private func learningBar(collected: Int, needed: ClosedRange<Int>) -> some View {
        let fraction = min(1, Double(collected) / Double(max(needed.lowerBound, 1)))
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.neutral(0.08))
                    Capsule()
                        .fill(Theme.Family.sleep)
                        .frame(width: geo.size.width * (settled ? fraction : 0))
                }
            }
            .frame(height: 6)
            Text("\(collected) night\(collected == 1 ? "" : "s") collected · about \(needed.lowerBound)–\(needed.upperBound) usually gives enough variation")
                .font(Theme.text(11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 260)
    }
}

/// Layout-preserving loading state: a title line and a subtle indeterminate
/// bar, never a giant spinner and never a fake percentage.
struct ZoonLoadingState: View {
    var title: String = "Updating last night…"

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(Theme.label(14, weight: .medium))
                .foregroundStyle(.secondary)
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Theme.Family.sleep)
                .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Empty states") {
    ScrollView {
        VStack(spacing: 24) {
            ZoonEmptyState(
                kind: .noData(
                    title: "No sleep yet",
                    message: "Wear your Apple Watch tonight and Zoon will start building your baseline.",
                    unlocks: ["Sleep Intelligence score", "Body clock and timing", "Recovery and body signals"]
                ),
                primaryAction: ("Open Health Access", {}),
                secondaryAction: ("Not now", {})
            )
            ZoonEmptyState(kind: .learning(collected: 7, typicallyNeeded: 14...21, message: "Zoon needs a spread of nights before it can start exploring patterns."))
            ZoonEmptyState(kind: .missingSensor(name: "Wrist temperature", message: "Not enough data yet. Available on compatible watches after sufficient overnight measurements."))
            ZoonEmptyState(kind: .failed(title: "Sleep data isn't available", message: "Zoon can't currently read sleep from Apple Health."), primaryAction: ("Try Again", {}))
            ZoonLoadingState()
        }
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
