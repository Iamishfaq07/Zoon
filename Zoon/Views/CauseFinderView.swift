import SwiftUI

/// "What affects your sleep?" — patterns in the user's own history, not
/// generic sleep-hygiene advice.
///
/// A dedicated screen for what used to be a handful of rows buried at the
/// bottom of the Journal tab. Four tabs, one per exposure state a logged
/// behaviour can honestly be in: a strong enough matched-pair signal to call
/// "helps" or "hurts"; tested with enough comparable nights but no effect
/// found; or logged too few times yet to say anything about at all. All
/// three non-obvious states are shown explicitly rather than left silently
/// absent -- "no effect" and "still learning" look identical from the
/// outside (both mean "nothing in Helps/Hurts") unless the app says which
/// one it actually is.
struct CauseFinderView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    private enum Tab: String, CaseIterable, Identifiable {
        case helps = "Helps", hurts = "Hurts", noEffect = "No Effect", learning = "Still Learning"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .helps
    @State private var showingExperimentPicker = false

    private var observations: [JournalCorrelator.Observation] {
        coordinator.journalObservations()
    }

    private var findings: [JournalCorrelator.Finding] {
        JournalCorrelator().findings(from: observations)
    }

    private var helpful: [JournalCorrelator.Finding] { findings.filter(\.isImprovement) }
    private var harmful: [JournalCorrelator.Finding] { findings.filter { !$0.isImprovement } }
    private var learning: [JournalCorrelator.LearningTag] {
        JournalCorrelator().stillLearning(from: observations)
    }
    private var noEffect: [BehaviorTag] {
        JournalCorrelator().testedNoEffect(from: observations)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                header
                experimentSection

                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                content
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Cause Finder")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExperimentPicker) {
            ExperimentPickerSheet { tag in
                preferences.startExperiment(tag)
                showingExperimentPicker = false
            }
        }
    }

    /// Active Guided Experiment, or a prompt to start one. See
    /// `GuidedExperiment` -- this doesn't run any statistics of its own,
    /// just reads the same findings/stillLearning/testedNoEffect results
    /// the tabs below already compute, filtered to one tracked tag.
    @ViewBuilder
    private var experimentSection: some View {
        if let tag = preferences.activeExperimentTag {
            GuidedExperimentCard(
                tag: tag,
                startDate: preferences.experimentStartDate,
                status: GuidedExperiment.status(for: tag, observations: observations, since: preferences.experimentStartDate),
                onEnd: { preferences.endExperiment() }
            )
        } else {
            Button {
                showingExperimentPicker = true
            } label: {
                Label("Start a guided experiment", systemImage: "flask")
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
            }
            .buttonStyle(.plain)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What affects your sleep?")
                .font(Theme.numeral(20))
            Text("Patterns found in your own sleep history -- an association, not proof of cause.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .helps:
            if helpful.isEmpty {
                emptyState("Nothing clears the bar yet. Keep logging -- a real helpful pattern will show up here once there's enough matched data.")
            } else {
                ForEach(helpful) { CauseFinderRow(finding: $0) }
            }
        case .hurts:
            if harmful.isEmpty {
                emptyState("Nothing clears the bar yet. That's a genuinely good sign, not a data gap.")
            } else {
                ForEach(harmful) { CauseFinderRow(finding: $0) }
            }
        case .noEffect:
            if noEffect.isEmpty {
                emptyState("Nothing here yet. Behaviours land in this tab once there's enough logged data to test them, whether or not a pattern turns up.")
            } else {
                ForEach(noEffect) { NoEffectRow(tag: $0) }
            }
        case .learning:
            if learning.isEmpty {
                emptyState("Tag a behaviour in the Journal on a few nights and it'll show up here while Zoon builds enough comparable nights to say anything about it.")
            } else {
                ForEach(learning) { LearningRow(tag: $0) }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }
}

private struct CauseFinderRow: View {
    let finding: JournalCorrelator.Finding
    @State private var expanded = false

    private var tint: Color {
        finding.isImprovement ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: finding.tag.symbol)
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.tag.label)
                            .font(Theme.label(14, weight: .semibold))
                        Text("Associated with \(finding.metric.format(finding.delta)) \(finding.metric.shortLabel)")
                            .font(Theme.text(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(finding.matchedPairCount) nights")
                            .font(Theme.text(10))
                            .foregroundStyle(.tertiary)
                        Text(finding.confidence.label)
                            .font(Theme.text(9, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(Theme.text(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .glassCard()
    }
}

private struct LearningRow: View {
    let tag: JournalCorrelator.LearningTag

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: tag.tag.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.neutral(0.06), in: Circle())
                Text(tag.tag.label)
                    .font(Theme.label(14, weight: .semibold))
                Spacer()
                Text("\(tag.loggedNights) / \(JournalCorrelator.minimumMatchedPairs)")
                    .font(Theme.text(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.neutral(0.08))
                    Capsule()
                        .fill(Theme.Metric.sleep)
                        .frame(width: geo.size.width * tag.progress)
                }
            }
            .frame(height: 5)

            Text("Needs about \(tag.remainingNights) more comparable night\(tag.remainingNights == 1 ? "" : "s") before Zoon will call anything a pattern.")
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }
}

private struct NoEffectRow: View {
    let tag: BehaviorTag

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tag.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Theme.neutral(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(tag.label)
                    .font(Theme.label(14, weight: .semibold))
                Text("No meaningful difference found in your data so far.")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }
}

private struct GuidedExperimentCard: View {
    let tag: BehaviorTag
    let startDate: Date?
    let status: GuidedExperiment.Status
    let onEnd: () -> Void

    private var daysTracking: Int? {
        guard let startDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: startDate, to: .now).day ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(Theme.Metric.sleep)
                    .frame(width: 24, height: 24)
                    .background(Theme.Metric.sleep.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Experiment: \(tag.label)")
                        .font(Theme.label(14, weight: .semibold))
                    if let daysTracking {
                        Text("Tracking for \(daysTracking) day\(daysTracking == 1 ? "" : "s")")
                            .font(Theme.text(11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            switch status {
            case .learning(let learning):
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.neutral(0.08))
                        Capsule()
                            .fill(Theme.Metric.sleep)
                            .frame(width: geo.size.width * learning.progress)
                    }
                }
                .frame(height: 5)
                Text("Needs about \(learning.remainingNights) more comparable night\(learning.remainingNights == 1 ? "" : "s") before there's an answer. Keep tagging \(tag.label.lowercased()) in the Journal.")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)

            case .result(let helpful, let harmful):
                ForEach(helpful + harmful) { finding in
                    Text(finding.headline)
                        .font(Theme.text(11, weight: .semibold))
                        .foregroundStyle(finding.isImprovement ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                }

            case .noEffect:
                Text("No meaningful difference found in your data so far.")
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
            }

            Button("End experiment", action: onEnd)
                .font(Theme.text(11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }
}

private struct ExperimentPickerSheet: View {
    let onSelect: (BehaviorTag) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(BehaviorTag.Category.allCases) { category in
                    Section(category.label) {
                        ForEach(category.tags) { tag in
                            Button {
                                onSelect(tag)
                            } label: {
                                Label(tag.label, systemImage: tag.symbol)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Track a behaviour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview("Cause Finder") {
    NavigationStack { CauseFinderView() }
        .zoonPreviewEnvironment()
}
