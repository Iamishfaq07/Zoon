import SwiftUI

/// Bundled sleep-science reading, styled after Apple Health's Browse tab —
/// a grid of colour-graded cards rather than a plain list, because this is
/// content meant to be skimmed and picked from, not scrolled top to bottom.
struct ArticlesView: View {

    @State private var selectedCategory: Article.Category?

    private var filtered: [Article] {
        guard let selectedCategory else { return Article.all }
        return Article.all.filter { $0.category == selectedCategory }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                categoryFilter

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { article in
                        NavigationLink {
                            ArticleDetailView(article: article)
                        } label: {
                            ArticleCard(article: article)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
            .padding(.top, 4)
        }
        .nightBackground()
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, label: "All")
                ForEach(Article.Category.allCases) { category in
                    filterChip(category, label: category.label)
                }
            }
        }
    }

    private func filterChip(_ category: Article.Category?, label: String) -> some View {
        let isOn = selectedCategory == category
        let tint = category?.tint ?? Theme.Metric.sleep

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedCategory = category }
            Haptics.tap()
        } label: {
            Text(label)
                .font(Theme.label(12, weight: .semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(isOn ? tint.opacity(0.3) : Theme.neutral(0.06))
                        .overlay {
                            Capsule().strokeBorder(isOn ? tint : Theme.cardStroke, lineWidth: 1)
                        }
                }
                .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// One card in the grid. Fixed height with a bottom-anchored gradient wash so
/// the symbol reads as illustration rather than a bare glyph on a flat tile.
private struct ArticleCard: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [article.category.tint.opacity(0.55), article.category.tint.opacity(0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: article.symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(14)
            }
            .frame(height: 84)

            VStack(alignment: .leading, spacing: 5) {
                Text(article.category.label.uppercased())
                    .font(Theme.text(9, weight: .bold))
                    .foregroundStyle(article.category.tint)
                    .tracking(0.5)
                Text(article.title)
                    .font(Theme.label(13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(article.readMinutes) min read")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
            }
            .padding(11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The reading view: a full-bleed gradient hero, then plain, generously
/// spaced paragraphs. No sidebar, no related-articles rail — this is content
/// meant to be read once and closed, not a destination to browse within.
struct ArticleDetailView: View {
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(article.body.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(Theme.text(15))
                            .foregroundStyle(.primary.opacity(0.9))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let takeaway = article.takeaway {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill")
                                .font(Theme.text(14))
                                .foregroundStyle(Theme.Metric.battery)
                            Text(takeaway)
                                .font(Theme.text(13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .glassCard()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .nightBackground()
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .top)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [article.category.tint.opacity(0.65), Color(red: 0.024, green: 0.031, blue: 0.078)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 220)

            Image(systemName: article.symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(article.category.label.uppercased())
                    .font(Theme.text(10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(0.5)
                Text(article.title)
                    .font(Theme.numeral(24))
                    .foregroundStyle(.white)
                Text(article.subtitle)
                    .font(Theme.label(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(article.readMinutes) min read")
                    .font(Theme.text(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(height: 220)
    }
}

#Preview("Learn") {
    NavigationStack { ArticlesView() }
        .preferredColorScheme(.dark)
}

#Preview("Article") {
    NavigationStack {
        ArticleDetailView(article: Article.all[0])
    }
    .preferredColorScheme(.dark)
}
