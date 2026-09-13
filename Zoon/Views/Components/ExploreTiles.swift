import SwiftUI

/// A grid of real, visible entry points to a tab's deeper screens.
///
/// These features moved out of Settings and landed as a row of small chips
/// at the very bottom of Insights, under every chart — which is the same
/// problem they were moved to solve, one screen further along. A chip at the
/// end of a long scroll is not a smaller version of a feature; it is a
/// hidden one.
///
/// So: full tiles, each with the one line that says what it is, placed high
/// in the tab whose subject they belong to rather than collected together in
/// a hub. A hub is what Settings was.
struct ExploreGrid<Content: View>: View {

    let title: String
    @ViewBuilder var tiles: Content

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZoonSectionHeader(title)
            LazyVGrid(columns: columns, spacing: 10) {
                tiles
            }
        }
    }
}

/// One entry: mark, name, and what it actually tells you.
struct ExploreTile<Destination: View>: View {

    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = Theme.Family.sleep
    @ViewBuilder var destination: Destination

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(Theme.text(17, weight: .semibold))
                    .foregroundStyle(tint)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)

                Text(title)
                    .font(Theme.label(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : 112, alignment: .topLeading)
            .padding(12)
            .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.neutral(0.10), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
