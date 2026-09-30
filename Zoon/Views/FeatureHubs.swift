import SwiftUI

// MARK: - Hub shell

/// One screen that holds several closely related ones, switched by a row of
/// chips at the top.
///
/// Zoon grew a screen per question: "What Zoon knows", "Your patterns",
/// "Cause Finder", "Sleep Playbook" and "Personal learning" each answered a
/// slice of "what affects my sleep", from five different rows in three
/// different places. Nobody holds five screens in their head. A hub puts the
/// slices of one question side by side, so there is one place to go and the
/// chips say what else is there. Every old way in -- a card, a tile, a deep
/// link -- now opens the hub on the matching chip.
struct FeatureHub<Choice: HubSection, Content: View>: View {

    let title: String
    @State private var selection: Choice
    @ViewBuilder let content: (Choice) -> Content

    @Namespace private var chipSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, initial: Choice, @ViewBuilder content: @escaping (Choice) -> Content) {
        self.title = title
        _selection = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content(selection)
            .id(selection)
            .transition(.opacity)
            .safeAreaInset(edge: .top, spacing: 0) { chips }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .hidesFloatingTabBar()
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Choice.allCases), id: \.self) { section in
                        chip(section)
                            .id(section)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, new in
                withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .background(.ultraThinMaterial.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.cardStroke).frame(height: 0.5)
        }
    }

    private func chip(_ section: Choice) -> some View {
        let selected = section == selection
        return Button {
            guard !selected else { return }
            Haptics.select()
            withAnimation(Motion.respecting(reduceMotion, Motion.standard)) { selection = section }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.symbol)
                    .font(Theme.text(12, weight: .semibold))
                Text(section.label)
                    .font(Theme.label(13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(selected ? Color.black : Theme.inkSecondary)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.Family.sleep)
                        .matchedGeometryEffect(id: "chip", in: chipSpace)
                } else {
                    Capsule().fill(Theme.neutral(0.08))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A chip on a hub: a short label and a symbol.
protocol HubSection: Hashable, CaseIterable where AllCases: RandomAccessCollection {
    var label: String { get }
    var symbol: String { get }
}

// MARK: - Your patterns

/// Everything about what goes with good and bad nights: what Zoon has
/// noticed, how sure it is, testing a hunch, what your best nights share and
/// what it has learned about you.
enum PatternsSection: String, HubSection {
    case noticed, proven, test, bestNights, learned

    var label: String {
        switch self {
        case .noticed: "Noticed"
        case .proven: "How sure"
        case .test: "Test it"
        case .bestNights: "Best nights"
        case .learned: "About you"
        }
    }

    var symbol: String {
        switch self {
        case .noticed: "sparkles"
        case .proven: "checkmark.seal"
        case .test: "flask"
        case .bestNights: "star"
        case .learned: "person.crop.circle"
        }
    }
}

struct PatternsHub: View {
    var initial: PatternsSection = .noticed

    var body: some View {
        FeatureHub(title: "Your patterns", initial: initial) { section in
            switch section {
            case .noticed: PatternsView()
            case .proven: EvidenceView()
            case .test: CauseFinderView()
            case .bestNights: SleepPlaybookView()
            case .learned: PersonalLearningView()
            }
        }
    }
}

// MARK: - Plan

enum PlanSection: String, HubSection {
    case tonight, tomorrow, travel

    var label: String {
        switch self {
        case .tonight: "Tonight"
        case .tomorrow: "Tomorrow"
        case .travel: "Travel"
        }
    }

    var symbol: String {
        switch self {
        case .tonight: "moon.stars.fill"
        case .tomorrow: "sunrise.fill"
        case .travel: "airplane"
        }
    }
}

struct PlanHub: View {
    var initial: PlanSection = .tonight

    var body: some View {
        FeatureHub(title: "Plan", initial: initial) { section in
            switch section {
            case .tonight: TonightRoutineView()
            case .tomorrow: ZoonTomorrowView()
            case .travel: TravelPlanView()
            }
        }
    }
}

// MARK: - Reports

enum ReportsSection: String, HubSection {
    case week, month, year, eras, doctor

    var label: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .eras: "Eras"
        case .doctor: "For a doctor"
        }
    }

    var symbol: String {
        switch self {
        case .week: "calendar.badge.clock"
        case .month: "moon.stars"
        case .year: "calendar"
        case .eras: "timeline.selection"
        case .doctor: "doc.text"
        }
    }
}

struct ReportsHub: View {
    var initial: ReportsSection = .week

    var body: some View {
        FeatureHub(title: "Reports", initial: initial) { section in
            switch section {
            case .week: ReportView()
            case .month: MonthRecapView()
            case .year: YearHeatmapView()
            case .eras: SleepErasView()
            case .doctor: ClinicianReportView()
            }
        }
    }
}

// MARK: - Your data

enum DataSection: String, HubSection {
    case overview, sources, arrived, repair

    var label: String {
        switch self {
        case .overview: "Overview"
        case .sources: "Sources"
        case .arrived: "Arrived"
        case .repair: "Fix"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "circle.hexagongrid.fill"
        case .sources: "sensor.tag.radiowaves.forward"
        case .arrived: "waveform.path.ecg"
        case .repair: "wrench.and.screwdriver"
        }
    }
}

struct DataHub: View {
    var initial: DataSection = .overview

    var body: some View {
        FeatureHub(title: "Your data", initial: initial) { section in
            switch section {
            case .overview: ModelHealthView()
            case .sources: SensorTruthView()
            case .arrived: DataQualityView()
            case .repair: DataRepairView()
            }
        }
    }
}

// MARK: - Learn

enum LearnSection: String, HubSection {
    case articles, words

    var label: String {
        switch self {
        case .articles: "Articles"
        case .words: "Words"
        }
    }

    var symbol: String {
        switch self {
        case .articles: "book.pages"
        case .words: "character.book.closed"
        }
    }
}

struct LearnHub: View {
    var initial: LearnSection = .articles

    var body: some View {
        FeatureHub(title: "Learn", initial: initial) { section in
            switch section {
            case .articles: ArticlesView()
            case .words: GlossaryView()
            }
        }
    }
}
