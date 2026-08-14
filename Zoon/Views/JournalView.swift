import SwiftUI
import SwiftData

/// Tag what you did; find out what it costs you.
///
/// The tagging UI is deliberately fast — one screen, chips, no modal per entry.
/// A journal that takes ninety seconds a day gets abandoned in a week, and an
/// abandoned journal produces no correlations at all.
struct JournalView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var findings: [JournalCorrelator.Finding] = []
    @State private var note: String = ""
    @FocusState private var noteFieldFocused: Bool

    // The source of truth for what's highlighted. `entry.contains(tag)` used
    // to be read straight from the SwiftData model on every render, but a tap
    // saved through the store and re-fetched a model instance SwiftUI hadn't
    // been told to re-observe -- the chip only caught up on the next render
    // triggered by something unrelated, like switching days. Owning the set
    // as plain @State makes a tap's visual result unconditional on that.
    @State private var selectedTagIdentifiers: Set<String> = []

    private var entry: JournalEntry {
        coordinator.journal.entryOrCreate(for: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stackSpacing) {
                    dayPicker
                    lifestyleInsightsCard
                    tagSections
                    noteCard
                    correlationsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .nightBackground()
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Multiline TextFields (`axis: .vertical`) treat Return as a
                // newline, not a submit — `onSubmit` never fires, so without
                // this the keyboard has no dismissal path at all and ends up
                // eating the first tap on anything underneath it.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteFieldFocused = false }
                }
                // Needed now that Journal is sheet-presented from every tab
                // rather than a tab in its own right — a sheet with no close
                // affordance relies entirely on the swipe-down gesture, which
                // isn't discoverable and doesn't work at all once a field is
                // focused and the keyboard is up.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .onChange(of: selectedDate) { _, _ in
                note = entry.note ?? ""
                selectedTagIdentifiers = Set(entry.tagIdentifiers)
            }
            .onChange(of: noteFieldFocused) { wasFocused, isFocused in
                if wasFocused, !isFocused {
                    coordinator.journal.setNote(note, on: selectedDate)
                }
            }
        }
    }

    // MARK: - Day picker

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Last two weeks, newest first. Beyond that, recall is poor
                // enough that the data would be noise.
                ForEach(0..<14, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
                    let day = Calendar.current.startOfDay(for: date)
                    dayChip(day)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let hasTags = !(coordinator.journal.entry(for: day)?.tagIdentifiers.isEmpty ?? true)

        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                    .font(Theme.text(10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(day, format: .dateTime.day())
                    .font(Theme.label(16, weight: .bold))
                Circle()
                    .fill(hasTags ? Theme.Metric.sleep : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 46, height: 62)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.Metric.sleep.opacity(0.25) : Theme.neutral(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.Metric.sleep : Theme.cardStroke,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lifestyle Insights

    /// Today's measured caffeine/alcohol/daylight/mindfulness, shown as
    /// reference alongside manual tagging -- not a substitute for it, and
    /// not shown for past days: the coordinator only ever holds *today's*
    /// figures (see `SleepDataCoordinator.todayLifestyleInsights`), so
    /// showing it while looking at another day would silently mislabel
    /// today's numbers as that day's.
    @ViewBuilder
    private var lifestyleInsightsCard: some View {
        if preferences.lifestyleInsightsEnabled,
           Calendar.current.isDateInToday(selectedDate),
           let insights = coordinator.todayLifestyleInsights,
           !insights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Measured today",
                    subtitle: "From Health, not the Journal -- reference alongside your tags.",
                    systemImage: "heart.text.square"
                )
                FlowLayout(spacing: 8) {
                    if let mg = insights.caffeineMg {
                        insightChip(symbol: "cup.and.saucer", text: "\(Int(mg.rounded())) mg caffeine")
                    }
                    if let drinks = insights.alcoholicBeverages, drinks > 0 {
                        insightChip(symbol: "wineglass", text: "\(String(format: "%.1f", drinks)) drinks")
                    }
                    if let minutes = insights.daylightMinutes {
                        insightChip(symbol: "sun.max", text: "\(Int(minutes.rounded())) min daylight")
                    }
                    if let minutes = insights.mindfulMinutes {
                        insightChip(symbol: "brain.head.profile", text: "\(Int(minutes.rounded())) min mindful")
                    }
                }
            }
            .glassCard()
        }
    }

    private func insightChip(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(Theme.text(11, weight: .medium))
            Text(text)
                .font(Theme.label(12, weight: .medium))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Theme.neutral(0.06), in: Capsule())
        .foregroundStyle(.secondary)
    }

    // MARK: - Tags

    private var tagSections: some View {
        VStack(spacing: Theme.stackSpacing) {
            ForEach(BehaviorTag.Category.allCases) { category in
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: category.label)
                    FlowLayout(spacing: 8) {
                        ForEach(category.tags) { tag in
                            tagChip(tag)
                        }
                    }
                }
                .glassCard()
            }
        }
    }

    private func tagChip(_ tag: BehaviorTag) -> some View {
        let isOn = selectedTagIdentifiers.contains(tag.rawValue)

        return Button {
            if isOn {
                selectedTagIdentifiers.remove(tag.rawValue)
            } else {
                selectedTagIdentifiers.insert(tag.rawValue)
            }
            coordinator.journal.toggle(tag, on: selectedDate)
            findings = JournalCorrelator().topFindingPerTag(from: coordinator.journalObservations())
            // Selection is a physical act here — the haptic confirms the toggle
            // landed without needing to look for a colour change.
            Haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tag.symbol)
                    .font(Theme.text(11, weight: .medium))
                Text(tag.label)
                    .font(Theme.label(12, weight: .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isOn ? Theme.Metric.sleep.opacity(0.3) : Theme.neutral(0.06))
                    .overlay {
                        Capsule().strokeBorder(
                            isOn ? Theme.Metric.sleep : Theme.cardStroke,
                            lineWidth: 1
                        )
                    }
            }
            .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Note",
                subtitle: "For your own recall. Notes are never analysed."
            )
            TextField("Anything else about today…", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .focused($noteFieldFocused)
                .submitLabel(.done)
        }
        .glassCard()
        .onDisappear { coordinator.journal.setNote(note, on: selectedDate) }
    }

    // MARK: - Correlations

    @ViewBuilder
    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "What your habits cost you",
                subtitle: "Behaviours with enough tagged nights to compare. Patterns, not proof of cause.",
                systemImage: "chart.line.uptrend.xyaxis"
            )

            if findings.isEmpty {
                Text("""
                    Nothing conclusive yet. Zoon needs at least \(JournalCorrelator.minimumMatchedPairs) \
                    nights with a behaviour that each have a comparable matched night without it before \
                    it will call anything a pattern.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(findings.prefix(6)) { finding in
                    CorrelationRow(finding: finding)
                }
            }
        }
        .glassCard()
    }

    private func reload() {
        note = entry.note ?? ""
        selectedTagIdentifiers = Set(entry.tagIdentifiers)
        findings = JournalCorrelator().topFindingPerTag(from: coordinator.journalObservations())
    }
}

struct CorrelationRow: View {
    let finding: JournalCorrelator.Finding

    private var tint: Color {
        finding.isImprovement ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: finding.tag.symbol)
                    .font(Theme.text(12))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.15), in: Circle())

                Text(finding.tag.label)
                    .font(Theme.label(13, weight: .semibold))

                Spacer()

                Text(String(format: "%+.0f%%", finding.percentChange))
                    .font(Theme.label(14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            Text(finding.detail)
                .font(Theme.text(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// Wrapping chip layout.
///
/// `Layout` rather than a `LazyVGrid`: chips have wildly different widths
/// ("Sauna" vs "Caffeine after 4pm") and a grid would either clip the long ones
/// or leave craters of whitespace around the short ones.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, availableWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, availableWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, availableWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if needed > availableWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview("Journal") {
    JournalView().zoonPreviewEnvironment()
}

#Preview("Correlations") {
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AppMockData.correlationFindings.prefix(5)) { finding in
                CorrelationRow(finding: finding)
            }
        }
        .glassCard()
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
