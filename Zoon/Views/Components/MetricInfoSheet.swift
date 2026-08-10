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
                explanation: explanation, relatedArticleID: relatedArticleID
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
}
