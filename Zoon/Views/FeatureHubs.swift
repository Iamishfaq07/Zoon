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
    /// Set when the hub is pushed from a tile with a zoom transition. The
    /// transition belongs to the pushed view, which is the hub, so the hub
    /// applies it and the screens inside are built without one.
    var zoomNamespace: Namespace.ID?
    var zoomID: String?

    @Namespace private var chipSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        initial: Choice,
        zoomNamespace: Namespace.ID? = nil,
        zoomID: String? = nil,
        @ViewBuilder content: @escaping (Choice) -> Content
    ) {
        self.title = title
        _selection = State(initialValue: initial)
        self.zoomNamespace = zoomNamespace
        self.zoomID = zoomID
        self.content = content
    }

    var body: some View {
        // Branching the view, not the transition value: `.zoom` and
        // `.automatic` are different concrete types (see BodyClockView).
        if let zoomNamespace, let zoomID {
            hub.navigationTransition(.zoom(sourceID: zoomID, in: zoomNamespace))
        } else {
            hub
        }
    }

    private var hub: some View {
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

// MARK: - Your body

/// The body-signal screens, one per signal, used to be reached from four
/// different cards with no way across. Side by side here.
enum BodySection: String, HubSection {
    case recovery, rhythm, energy, breathing, signals

    var label: String {
        switch self {
        case .recovery: "Recovery"
        case .rhythm: "Rhythm"
        case .energy: "Energy"
        case .breathing: "Breathing"
        case .signals: "All signals"
        }
    }

    var symbol: String {
        switch self {
        case .recovery: "heart.fill"
        case .rhythm: "metronome"
        case .energy: "bolt.fill"
        case .breathing: "lungs.fill"
        case .signals: "dot.radiowaves.left.and.right"
        }
    }
}

struct BodyHub: View {
    var initial: BodySection = .recovery
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    @Environment(SleepDataCoordinator.self) private var coordinator

    var body: some View {
        FeatureHub(title: "Your body", initial: initial, zoomNamespace: zoomNamespace, zoomID: zoomID) { section in
            switch section {
            case .recovery: RecoveryDetailView()
            case .rhythm: RegularityDetailView()
            case .energy:
                if let context = coordinator.state.context {
                    EnergyDetailView(context: context)
                } else {
                    ZoonEmptyState(
                        kind: .noData(
                            title: "No energy picture yet",
                            message: "Zoon needs last night's sleep before it can forecast today's energy.",
                            unlocks: ["Energy through the day", "Daily load"]
                        )
                    )
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .nightBackground()
                }
            case .breathing: BreathingHealthView()
            case .signals: HealthRadarView()
            }
        }
    }
}

// MARK: - Sleep need

/// How much sleep you need and how much you are owed are one question asked
/// two ways -- the need tonight includes paying some of it back -- and they
/// were two screens.
enum NeedSection: String, HubSection {
    case need, owed

    var label: String {
        switch self {
        case .need: "Your need"
        case .owed: "Owed"
        }
    }

    var symbol: String {
        switch self {
        case .need: "bed.double.fill"
        case .owed: "hourglass"
        }
    }
}

struct NeedHub: View {
    var initial: NeedSection = .need
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    var body: some View {
        FeatureHub(title: "Sleep need", initial: initial, zoomNamespace: zoomNamespace, zoomID: zoomID) { section in
            switch section {
            case .need: SleepNeedView()
            case .owed: SleepDebtView()
            }
        }
    }
}

// MARK: - Inline switcher

/// A chip row over one card slot, for sections that stacked several cards of
/// the same kind -- four charts in a row, three comparison cards -- where
/// people read the first and scroll past the rest. One slot, and the chips
/// say what else it can show.
struct InlineChipSwitcher<Choice: HubSection, Content: View>: View {
    @State private var selection: Choice
    let choices: [Choice]
    @ViewBuilder let content: (Choice) -> Content

    @Namespace private var chipSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initial: Choice, choices: [Choice]? = nil, @ViewBuilder content: @escaping (Choice) -> Content) {
        _selection = State(initialValue: initial)
        self.choices = choices ?? Array(Choice.allCases)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(choices, id: \.self) { choice in
                        let selected = choice == selection
                        Button {
                            guard !selected else { return }
                            Haptics.select()
                            withAnimation(Motion.respecting(reduceMotion, Motion.standard)) { selection = choice }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: choice.symbol)
                                    .font(Theme.text(11, weight: .semibold))
                                Text(choice.label)
                                    .font(Theme.label(12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
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
            }
            content(selection)
                .id(selection)
                .transition(.opacity)
        }
    }
}
