import SwiftUI

/// The CONSTELLATION form: things Zoon has evidence about, and how they
/// connect, as a graph the reader can walk rather than a list of sentences.
///
/// ```
///        Caffeine
///            \
///  Daylight — SLEEP — Bedtime
///            /
///          HRV
/// ```
///
/// A relationship is a fact about *two* things, and prose has to name both
/// every time ("late caffeine is associated with 14 minutes more time to
/// fall asleep") which makes ten relationships ten sentences that share
/// eight words. A graph says the shared part once, in the layout, and
/// spends its ink on what differs: which pairs are joined at all, how
/// strongly, and how well established.
///
/// Deliberate restrictions, from the redesign brief and from what the data
/// can actually support:
///
/// * **One focus at a time.** Only the focused node's own edges are drawn.
///   A dozen nodes fully connected is forty edges and no readable structure;
///   this is a graph to walk, not a hairball to admire.
/// * **Evidence is not colour.** Edge *thickness* is effect magnitude and
///   the *dash pattern* is evidence strength, so both survive greyscale,
///   colour blindness and Increased Contrast. Tint only groups by family.
/// * **Nodes move only on selection.** No continuous drift. Idle motion in
///   a data graphic implies data that is changing, and costs battery to say
///   something untrue.
/// * **Nothing here is causal**, and the caller's edge detail says so. The
///   layout puts the focus in the middle because it is the subject of the
///   comparison, not because it is the cause or the effect.
struct ZoonConstellation: View {

    struct Node: Identifiable, Hashable {
        let id: String
        let label: String
        let symbol: String
        var tint: Color = Theme.Family.sleep
    }

    /// An evidenced relationship between two nodes. `magnitude` is
    /// pre-normalised to 0...1 by the caller against its own set, because
    /// only the caller knows whether 14 minutes is a lot.
    struct Edge: Identifiable, Hashable {
        let from: String
        let to: String
        let magnitude: Double
        let evidence: MetricConfidence
        /// One plain sentence for the detail sheet and for VoiceOver.
        let detail: String

        var id: String { "\(from)-\(to)" }
    }

    let nodes: [Node]
    let edges: [Edge]
    /// Node id the graph opens on. Falls back to the first node.
    var initialFocus: String?

    @State private var focusID: String?
    @State private var selectedEdge: Edge?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var focus: Node? {
        nodes.first { $0.id == (focusID ?? initialFocus) } ?? nodes.first
    }

    /// Edges touching the focus, strongest first, capped so the ring stays
    /// legible on the smallest iPhone.
    private var focusEdges: [Edge] {
        guard let focus else { return [] }
        return edges
            .filter { $0.from == focus.id || $0.to == focus.id }
            .sorted { $0.magnitude > $1.magnitude }
            .prefix(6)
            .map { $0 }
    }

    /// The nodes on the ring: the far end of each focus edge.
    private var neighbours: [Node] {
        guard let focus else { return [] }
        return focusEdges.compactMap { edge in
            let otherID = edge.from == focus.id ? edge.to : edge.from
            return nodes.first { $0.id == otherID }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            graph
            legend
        }
        .sheet(item: $selectedEdge) { edge in
            edgeSheet(edge)
        }
    }

    // MARK: - Graph

    private var graph: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // Leaves room for the ring labels at large text sizes.
            let radius = size / 2 - (dynamicTypeSize.isAccessibilitySize ? 62 : 46)

            ZStack {
                ForEach(Array(focusEdges.enumerated()), id: \.element.id) { index, edge in
                    let point = ringPoint(index: index, center: center, radius: radius)
                    edgeLine(edge, from: center, to: point)
                }

                ForEach(Array(neighbours.enumerated()), id: \.offset) { index, node in
                    let point = ringPoint(index: index, center: center, radius: radius)
                    nodeChip(node, isFocus: false)
                        .position(point)
                        .onTapGesture { refocus(node) }
                }

                if let focus {
                    nodeChip(focus, isFocus: true)
                        .position(center)
                }
            }
            .animation(Motion.respecting(reduceMotion, Motion.entrance), value: focusID)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 340 : 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connection map")
        .accessibilityValue(graphSummary)
    }

    /// Neighbours are spread evenly, starting at the top. Strongest edge
    /// first, so the eye's first stop is the biggest relationship.
    private func ringPoint(index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let count = max(neighbours.count, 1)
        let angle = -Double.pi / 2 + (2 * Double.pi * Double(index) / Double(count))
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    /// Thickness = magnitude, dash = evidence. Both readable without colour.
    private func edgeLine(_ edge: Edge, from: CGPoint, to: CGPoint) -> some View {
        let width = 1 + edge.magnitude * 4
        return Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            (focus?.tint ?? Theme.Family.sleep).opacity(selectedEdge == nil ? 0.55 : selectedEdge?.id == edge.id ? 0.95 : 0.18),
            style: StrokeStyle(lineWidth: width, lineCap: .round, dash: Self.dash(for: edge.evidence))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.select()
            selectedEdge = edge
        }
        .accessibilityElement()
        .accessibilityLabel(edge.detail)
        .accessibilityHint("Opens the evidence behind this connection")
        .accessibilityAddTraits(.isButton)
    }

    /// Solid for the best-established relationships, progressively more
    /// broken as the evidence thins -- a dotted line reads as provisional
    /// without needing a key.
    static func dash(for evidence: MetricConfidence) -> [CGFloat] {
        switch evidence {
        case .high: []
        case .moderate: [7, 4]
        case .low: [3, 4]
        case .insufficient: [1.5, 4]
        }
    }

    private func nodeChip(_ node: Node, isFocus: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: node.symbol)
                .font(Theme.text(isFocus ? 18 : 13, weight: .semibold))
                .foregroundStyle(isFocus ? Color.white : node.tint)
                .frame(width: isFocus ? 52 : 34, height: isFocus ? 52 : 34)
                .background {
                    Circle()
                        .fill(isFocus ? node.tint : node.tint.opacity(0.16))
                        .overlay(Circle().strokeBorder(node.tint.opacity(isFocus ? 0 : 0.5), lineWidth: 1))
                }
            Text(node.label)
                .font(isFocus ? Theme.label(13, weight: .semibold) : Theme.supportingLabel)
                .foregroundStyle(isFocus ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 92)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isFocus ? "\(node.label), current focus" : node.label)
        .accessibilityHint(isFocus ? "" : hint(for: node))
        .accessibilityAddTraits(isFocus ? [] : .isButton)
    }

    /// Matches what the tap actually does -- see `refocus`.
    private func hint(for node: Node) -> String {
        let own = edges.filter { $0.from == node.id || $0.to == node.id }
        return own.count > 1 ? "Refocuses the map on \(node.label)" : "Shows the evidence for this connection"
    }

    /// Refocusing is only offered when it would actually reveal something.
    ///
    /// In a star-shaped graph -- which is what the correlator's findings
    /// make -- a leaf has exactly one edge, the one already on screen, so
    /// recentring on it rearranges the picture and shows nothing new. Where
    /// that is the case the tap opens the edge's evidence instead, which is
    /// what someone tapping a node with one connection wants.
    private func refocus(_ node: Node) {
        guard node.id != focus?.id else { return }
        let own = edges.filter { $0.from == node.id || $0.to == node.id }
        guard own.count > 1 else {
            if let only = own.first {
                Haptics.select()
                selectedEdge = only
            }
            return
        }
        Haptics.select()
        selectedEdge = nil
        focusID = node.id
    }

    // MARK: - Legend

    /// Named in text because thickness and dash need one explanation the
    /// first time, and because a legend is how a reader learns the grammar
    /// the rest of the app then reuses.
    private var legend: some View {
        HStack(spacing: 18) {
            legendItem("Thicker line", "Bigger difference")
            legendItem("Solid line", "Stronger evidence")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func legendItem(_ term: String, _ meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(term)
                .font(Theme.supportingLabel)
                .foregroundStyle(.secondary)
            Text(meaning)
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Edge detail

    private func edgeSheet(_ edge: Edge) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(edge.detail)
                    .font(Theme.text(16))
                    .fixedSize(horizontal: false, vertical: true)

                ZoonEvidenceBadge(confidence: edge.evidence)

                Text("Zoon found this by comparing your own nights. It's a pattern in your data, not proof that one causes the other — nights like these usually differ in other ways too.")
                    .font(Theme.evidence)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .nightBackground()
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Accessibility

    /// The whole graph in one sentence, so VoiceOver does not require a walk
    /// of the ring to learn what is on it.
    private var graphSummary: String {
        guard let focus else { return "No connections yet." }
        guard !focusEdges.isEmpty else {
            return "\(focus.label) has no connections yet."
        }
        let names = neighbours.map(\.label)
        return "\(focus.label), connected to \(names.joined(separator: ", ")). \(focusEdges.count.pluralized("connection")), strongest first."
    }
}

// MARK: - Building from Zoon's own evidence

extension ZoonConstellation {
    /// Builds the map from what the correlator already found.
    ///
    /// Sleep is the hub, and the topology really is a star: every finding
    /// the correlator produces has a sleep outcome on one end, because that
    /// is what it compares. Behaviour-to-behaviour edges are deliberately
    /// *not* invented to make the picture look more graph-like -- no engine
    /// in the app measures whether two behaviours co-occur, and drawing a
    /// line for it would be a claim with nothing behind it.
    ///
    /// Magnitude is normalised within this set: the biggest effect present
    /// draws the thickest line. That is the only honest normalisation
    /// available, since minutes of latency and percent of efficiency have no
    /// shared scale, and it means thickness is always "big *for you*".
    static func fromFindings(_ findings: [JournalCorrelator.Finding]) -> (nodes: [Node], edges: [Edge])? {
        guard !findings.isEmpty else { return nil }

        // One edge per behaviour: its strongest finding. A tag with four
        // findings would otherwise fan out four near-identical lines.
        var strongest: [BehaviorTag: JournalCorrelator.Finding] = [:]
        for finding in findings {
            let incumbent = strongest[finding.tag]
            if incumbent == nil || abs(finding.delta) > abs(incumbent!.delta) {
                strongest[finding.tag] = finding
            }
        }

        let hub = Node(id: "sleep", label: "Sleep", symbol: "moon.stars.fill", tint: Theme.Family.sleep)
        var nodes: [Node] = [hub]
        var edges: [Edge] = []

        // Relative effect, so metrics in different units are comparable at
        // all -- the same ranking `JournalCorrelator` uses for ordering.
        let scale = strongest.values.map { relativeEffect($0) }.max() ?? 1

        for (tag, finding) in strongest.sorted(by: { abs($0.value.delta) > abs($1.value.delta) }) {
            nodes.append(Node(
                id: tag.rawValue,
                label: tag.label,
                symbol: tag.symbol,
                tint: finding.isImprovement ? Theme.Family.recovery : Theme.Family.attention
            ))
            edges.append(Edge(
                from: hub.id,
                to: tag.rawValue,
                magnitude: min(relativeEffect(finding) / max(scale, 0.0001), 1),
                evidence: ZoonPairedPlot.metricConfidence(finding.confidence),
                detail: finding.headline
            ))
        }

        return (nodes, edges)
    }

    private static func relativeEffect(_ finding: JournalCorrelator.Finding) -> Double {
        abs(finding.delta) / max(abs(finding.matchedMedian), 1)
    }
}

#Preview("Constellation") {
    ScrollView {
        ZoonConstellation(
            nodes: [
                .init(id: "sleep", label: "Sleep", symbol: "moon.stars.fill", tint: Theme.Family.sleep),
                .init(id: "caffeine", label: "Caffeine", symbol: "cup.and.saucer", tint: Theme.Family.attention),
                .init(id: "daylight", label: "Daylight", symbol: "sun.max", tint: Theme.Family.circadian),
                .init(id: "bedtime", label: "Bedtime", symbol: "bed.double", tint: Theme.Family.sleep),
                .init(id: "hrv", label: "HRV", symbol: "waveform.path.ecg", tint: Theme.Family.bodySignals),
            ],
            edges: [
                .init(from: "sleep", to: "caffeine", magnitude: 0.9, evidence: .moderate,
                      detail: "On nights after caffeine late in the day, your sleep efficiency was about 4% lower."),
                .init(from: "sleep", to: "daylight", magnitude: 0.5, evidence: .low,
                      detail: "After mornings with more daylight, you fell asleep about 12 minutes earlier."),
                .init(from: "sleep", to: "bedtime", magnitude: 0.7, evidence: .high,
                      detail: "Your most consistent bedtimes came with your highest sleep scores."),
                .init(from: "sleep", to: "hrv", magnitude: 0.3, evidence: .low,
                      detail: "Your higher-HRV mornings followed your longer nights."),
                .init(from: "caffeine", to: "hrv", magnitude: 0.4, evidence: .low,
                      detail: "Caffeine days showed slightly lower overnight HRV."),
            ],
            initialFocus: "sleep"
        )
        .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}

/// Large text is where the ring labels and the 92pt label cap are most
/// likely to collide.
#Preview("Constellation - large text") {
    ZoonConstellation(
        nodes: [
            .init(id: "sleep", label: "Sleep", symbol: "moon.stars.fill", tint: Theme.Family.sleep),
            .init(id: "caffeine", label: "Caffeine", symbol: "cup.and.saucer", tint: Theme.Family.attention),
            .init(id: "bedtime", label: "Bedtime", symbol: "bed.double", tint: Theme.Family.sleep),
        ],
        edges: [
            .init(from: "sleep", to: "caffeine", magnitude: 0.9, evidence: .moderate, detail: "Caffeine late in the day, lower efficiency."),
            .init(from: "sleep", to: "bedtime", magnitude: 0.6, evidence: .high, detail: "Consistent bedtimes, higher scores."),
        ],
        initialFocus: "sleep"
    )
    .padding()
    .nightBackground()
    .zoonPreviewEnvironment()
    .environment(\.dynamicTypeSize, .accessibility3)
}
