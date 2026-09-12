import SwiftUI

/// Sleep science on the screen it explains, rather than in a library.
///
/// All eight articles were reachable only from More → Learn. That is the one
/// place nobody is standing when they look at their sleep debt and wonder
/// what sleep debt actually is — the question arrives on the chart, so the
/// answer belongs on the chart. Apple Health reads the same way: an article
/// about heart rate variability sits under the heart rate variability graph.
///
/// Deliberately quiet. This is an offer, not a call to action: one hairline,
/// a symbol, a title and how long it takes. It sits at the end of a screen,
/// never above the data it explains, because someone who already knows what
/// REM is should never have to scroll past an explanation of it.
struct RelatedReading: View {

    let placement: Article.Placement
    /// Shown above the row. Named for what the reading answers rather than
    /// labelled "Learn", which says where it came from instead.
    var title: String = "Worth reading"

    private var articles: [Article] { Article.reading(for: placement) }

    var body: some View {
        if articles.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ZoonSectionHeader(title)
                    .padding(.bottom, 6)

                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.cardStroke)
                            .frame(height: 1)
                    }

                    NavigationLink {
                        ArticleDetailView(article: article)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: article.symbol)
                                .font(Theme.text(15))
                                .foregroundStyle(Theme.Family.sleep)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(article.title)
                                    .font(Theme.label(15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(article.readMinutes) min read")
                                    .font(Theme.text(12))
                                    .foregroundStyle(Theme.inkTertiary)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(Theme.text(11, weight: .semibold))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(article.title), \(article.readMinutes) minute read")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Related reading") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RelatedReading(placement: .sleepDebt)
                RelatedReading(placement: .recovery)
                RelatedReading(placement: .tonightRoutine)
            }
            .padding()
        }
        .nightBackground()
    }
    .zoonPreviewEnvironment()
}
