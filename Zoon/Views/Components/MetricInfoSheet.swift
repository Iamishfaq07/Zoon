import SwiftUI

/// The three things a metric sheet has to answer that `SensorTruth` cannot.
///
/// `SensorTruth.Fact` says what a number *is* and how it was obtained --
/// fixed properties of the quantity, identical for everyone. These three are
/// properties of *today's* number for *this* person: how much to trust it,
/// what normal looks like for them, and what to do about it. They change
/// night to night, so they are passed in by the card that already computed
/// them rather than looked up from a table.
///
/// Every field is optional and the whole struct defaults to empty, so a
/// metric that can only answer one of the three answers one of the three.
/// Saying nothing is better than filling the gap with a generic sentence
/// that is true of everybody: "normal is 7-9 hours" is not a baseline.
struct MetricFacets: Equatable {
    /// How much to trust the number as shown, when the metric tracks it.
    var confidence: MetricConfidence?
    /// Why it sits at that level -- which input is thin, not a restatement
    /// of the band. Shown only alongside `confidence`.
    var confidenceReason: String?
    /// What this person's own typical range is. Not a population range:
    /// if no personal baseline has been learned yet, leave it nil and let
    /// the sheet stay quiet.
    var baseline: String?
    /// The single thing worth doing about it. One sentence, imperative,
    /// and omitted entirely when the honest answer is "nothing".
    var action: String?

    var isEmpty: Bool {
        confidence == nil && baseline == nil && action == nil
    }
}

/// The tap target every previously-static card on Today now has: an "i"
/// button that opens a short sheet explaining what the metric means, with a
/// link into the matching `Learn` article when one exists.
///
/// Deliberately a sheet, not a push. These aren't destinations you browse
/// from — you tap one, read a paragraph, and dismiss back to exactly where
/// you were, which a `NavigationLink` push (with its own back-stack) makes
/// clumsier than it needs to be for a single paragraph of context.
struct MetricInfoButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let explanation: [String]
    var relatedArticleID: String? = nil
    /// When set, the sheet states what kind of claim this number is --
    /// measured, calculated, estimated or self-reported -- above the prose.
    /// Optional so existing call sites are unchanged; a metric with no
    /// mapping simply shows what it always did.
    var quantity: SensorTruth.Quantity? = nil
    /// Confidence, personal baseline and next action, when the caller knows
    /// them. Defaults to empty so every existing call site is unchanged.
    var facets = MetricFacets()

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
            Haptics.tap()
        } label: {
            Image(systemName: "info.circle")
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkTertiary)
        }
        .buttonStyle(.plain)
        // This button is repeated beside most metrics in the app, so an
        // unlabelled one is not one bad control but dozens: VoiceOver read
        // every single one as "info circle".
        .accessibilityLabel("About \(title)")
        .accessibilityHint("Explains what this metric measures")
        .sheet(isPresented: $isPresented) {
            MetricInfoSheet(
                title: title, symbol: symbol, tint: tint,
                explanation: explanation, relatedArticleID: relatedArticleID,
                quantity: quantity, facets: facets
            )
        }
    }
}

private struct MetricInfoSheet: View {
    let title: String
    let symbol: String
    let tint: Color
    let explanation: [String]
    let relatedArticleID: String?
    let quantity: SensorTruth.Quantity?
    var facets = MetricFacets()

    @Environment(\.dismiss) private var dismiss

    private var relatedArticle: Article? {
        relatedArticleID.flatMap { id in Article.all.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: symbol)
                            .font(Theme.text(24))
                            .foregroundStyle(tint)
                            .frame(width: 46, height: 46)
                            .background(tint.opacity(0.15), in: Circle())
                        Text(title)
                            .font(Theme.numeral(22))
                    }

                    // Provenance and facets are one panel, not two boxes.
                    // Both answer "how should I read this number"; giving
                    // each its own card made the sheet a stack of three
                    // identical rectangles, which flattens the hierarchy
                    // instead of expressing it. A hairline separates the
                    // fixed properties of the quantity from the ones that
                    // are about tonight.
                    if quantity != nil || !facets.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            if let quantity {
                                provenance(SensorTruth.fact(for: quantity))
                            }
                            if quantity != nil && !facets.isEmpty {
                                Rectangle()
                                    .fill(Theme.cardStroke)
                                    .frame(height: 1)
                            }
                            if !facets.isEmpty {
                                facetBlock
                            }
                        }
                        .padding(12)
                        .glassCard()
                    }

                    ForEach(Array(explanation.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(Theme.text(14))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let relatedArticle {
                        NavigationLink {
                            ArticleDetailView(article: relatedArticle)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "book.pages.fill")
                                    .foregroundStyle(relatedArticle.category.tint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Read more").font(Theme.label(13, weight: .semibold))
                                    Text(relatedArticle.title).font(Theme.text(11)).foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(Theme.text(11, weight: .semibold))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .padding(12)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .nightBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Under the provenance lines, above the prose, for the same reason
    /// provenance sits there: how much to trust tonight's number changes how
    /// the paragraphs underneath should be read, and a caveat that arrives
    /// after the explanation is a footnote.
    ///
    /// A hairline separates the two halves because they are different kinds
    /// of claim. Provenance is a fixed property of the quantity and is the
    /// same for everybody; these three are about tonight, for this person,
    /// and change by the night.
    @ViewBuilder
    private var facetBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let confidence = facets.confidence {
                facetRow(
                    symbol: "gauge.with.dots.needle.bottom.50percent",
                    label: confidence.label,
                    tint: confidenceTint(confidence),
                    detail: facets.confidenceReason
                )
            }
            if let baseline = facets.baseline {
                facetRow(
                    symbol: "chart.line.flattrend.xyaxis",
                    label: "Your usual",
                    tint: Theme.inkSecondary,
                    detail: baseline
                )
            }
            if let action = facets.action {
                facetRow(
                    symbol: "arrow.forward.circle.fill",
                    label: "What to do",
                    tint: tint,
                    detail: action
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func facetRow(symbol: String, label: String, tint: Color, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(Theme.text(12, weight: .semibold))
                .foregroundStyle(tint)
                // Fixed width so the three rows' text edges line up even
                // though the glyphs differ in width.
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.label(12, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Warm at the top, cooling as the claim weakens -- the same direction
    /// `tintFor(_:)` takes provenance, so the two blocks in this sheet do
    /// not teach opposite colour vocabularies.
    private func confidenceTint(_ confidence: MetricConfidence) -> Color {
        switch confidence {
        case .high: Theme.Metric.recoveryHigh
        case .moderate: Theme.Metric.recoveryMid
        case .low: Theme.Metric.recoveryLow
        case .insufficient: Theme.inkSecondary
        }
    }

    /// Sits above the explanatory prose rather than below it. Whether a
    /// number was measured or guessed changes how the paragraph underneath
    /// should be read, so it has to arrive first -- a provenance note at the
    /// bottom is a footnote, and footnotes are what people skip.
    private func provenance(_ fact: SensorTruth.Fact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: fact.provenance))
                    .font(Theme.text(11, weight: .semibold))
                Text(fact.provenance.label)
                    .font(Theme.label(12, weight: .semibold))
            }
            .foregroundStyle(tintFor(fact.provenance))

            Text(fact.quantity.whatItIs)
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(fact.quantity.limit)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if fact.isWeakenedByItsInputs, let first = fact.weakenedBy.first {
                Text("Shown as \(fact.provenance.label.lowercased()) because \(first.label.lowercased()) is.")
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func symbol(for provenance: SensorTruth.Provenance) -> String {
        switch provenance {
        case .measured: "sensor.tag.radiowaves.forward.fill"
        case .derived: "function"
        case .inferred: "wand.and.stars"
        case .selfReported: "hand.raised.fill"
        }
    }

    /// Cools as the claim weakens, matching the Evidence screen's tiers so
    /// the two teach the same colour vocabulary.
    private func tintFor(_ provenance: SensorTruth.Provenance) -> Color {
        switch provenance {
        case .measured: Theme.Metric.recoveryHigh
        case .derived: Theme.Metric.strain
        case .inferred: Theme.Metric.sleep
        case .selfReported: Theme.inkSecondary
        }
    }
}

// The sheet, not the button. The button is a 13pt "i" glyph with nothing to
// look at; the sheet is where the layout decisions live, and it is only
// reachable at runtime behind a tap, which is exactly the kind of thing that
// ships wrong.

/// Sleep stages is the most interesting provenance case in the app: Apple's
/// staging is a model's guess from indirect signals, so this renders the
/// "Estimated" capsule rather than the reassuring one.
#Preview("Metric info - estimated") {
    MetricInfoSheet(
        title: "Sleep Stages",
        symbol: "chart.bar.fill",
        tint: Theme.Metric.sleep,
        explanation: [
            "Core, Deep and REM are the phases your night cycles through.",
            "Deep sleep clusters early; REM lengthens towards morning."
        ],
        relatedArticleID: nil,
        quantity: .sleepStages
    )
}

/// A directly-measured quantity, for the other end of the capsule's range.
#Preview("Metric info - measured") {
    MetricInfoSheet(
        title: "Resting Heart Rate",
        symbol: "heart.fill",
        tint: Theme.Metric.hrv,
        explanation: ["Your lowest sustained heart rate while you slept."],
        relatedArticleID: nil,
        quantity: .restingHeartRate
    )
}

/// No quantity: the shape every call site had before provenance existed, and
/// still the shape of any metric with no mapping. The capsule should be
/// absent rather than empty.
#Preview("Metric info - no provenance") {
    MetricInfoSheet(
        title: "Sleep Score",
        symbol: "moon.stars.fill",
        tint: Theme.Metric.sleep,
        explanation: ["A single number combining duration, quality and timing."],
        relatedArticleID: nil,
        quantity: nil
    )
}

/// All three facets at once, which no single real metric supplies today --
/// the rows have to line up with each other regardless, and the only place
/// that is visible is a preview that forces the full set.
#Preview("Metric info - facets") {
    MetricInfoSheet(
        title: "Daily Load",
        symbol: "flame.fill",
        tint: Theme.Metric.strain,
        explanation: [
            "A cardiovascular load score built from your heart rate through the day, weighted by how far above resting it ran and for how long."
        ],
        relatedArticleID: nil,
        quantity: nil,
        facets: MetricFacets(
            confidence: .moderate,
            confidenceReason: "Zones from an age-estimated maximum heart rate, not one you've hit.",
            baseline: "You usually land between 8 and 12 on a weekday.",
            action: "Protect your usual bedtime tonight; a strenuous day is the one most easily undone by a late one."
        )
    )
}

/// The weakest facet on its own. A metric that knows only its confidence
/// should still render a block that reads as deliberate rather than as a
/// card with two rows missing.
#Preview("Metric info - one facet") {
    MetricInfoSheet(
        title: "Sleep Intelligence Score",
        symbol: "brain.head.profile",
        tint: Theme.Metric.sleep,
        explanation: ["Combines five sleep-period components."],
        relatedArticleID: nil,
        quantity: nil,
        facets: MetricFacets(
            confidence: .low,
            confidenceReason: "Scored without Timing and Stage Pattern — there wasn't enough data for them tonight."
        )
    )
}
