import SwiftUI

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

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
            Haptics.tap()
        } label: {
            Image(systemName: "info.circle")
                .font(Theme.text(13))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            MetricInfoSheet(
                title: title, symbol: symbol, tint: tint,
                explanation: explanation, relatedArticleID: relatedArticleID,
                quantity: quantity
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

                    if let quantity {
                        provenance(SensorTruth.fact(for: quantity))
                    }

                    ForEach(Array(explanation.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(Theme.text(14))
                            .foregroundStyle(.secondary)
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
                                    Text(relatedArticle.title).font(Theme.text(11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(Theme.text(11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
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
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(fact.quantity.limit)
                .font(Theme.text(12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if fact.isWeakenedByItsInputs, let first = fact.weakenedBy.first {
                Text("Shown as \(fact.provenance.label.lowercased()) because \(first.label.lowercased()) is.")
                    .font(Theme.text(12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard()
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
        case .selfReported: .secondary
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
