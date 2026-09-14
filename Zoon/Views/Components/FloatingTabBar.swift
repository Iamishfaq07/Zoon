import SwiftUI

/// The four tabs as a floating glass capsule.
///
/// Replaces the system tab bar's opaque strip. Two things had to come with
/// it, and the second is the one that bites: a floating bar sits *over* the
/// content, so every scroll view underneath needs bottom room or its last
/// row lives permanently behind the glass. That inset is applied centrally
/// in `RootView` rather than left to each tab to remember — the screenshots
/// in this repo show exactly what forgetting looks like, with the final row
/// of several screens half-covered.
struct FloatingTabBar<Tab: Hashable>: View {

    struct Item: Identifiable {
        let tab: Tab
        let title: String
        let symbol: String
        var id: String { title }
    }

    let items: [Item]
    @Binding var selection: Tab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                button(item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().stroke(Theme.neutral(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
    }

    /// Each tab's own identifier.
    ///
    /// The first attempt put one identifier on the bar and had the tests
    /// scope their queries to it. That element never resolved — an
    /// identifier on a styled `HStack` is not reliably exposed as a
    /// container, and the run failed with "No matches found for ... 'zoon
    /// .tabBar' IN identifiers". Identifying the buttons themselves needs no
    /// container to exist, and it also avoids matching a label like "Sleep"
    /// that appears elsewhere on the screen.
    static func identifier(for title: String) -> String {
        "zoon.tab.\(title.lowercased())"
    }

    private func button(_ item: Item) -> some View {
        let isSelected = selection == item.tab

        return Button {
            guard !isSelected else { return }
            Haptics.select()
            withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                selection = item.tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(Theme.text(16, weight: .semibold))
                    .dynamicTypeSize(...DynamicTypeSize.large)
                Text(item.title)
                    .font(Theme.label(10, weight: .semibold))
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            .foregroundStyle(isSelected ? Theme.Family.sleep : Theme.inkTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.Family.sleep.opacity(0.16))
                        // One shape that moves between tabs rather than four
                        // that fade in and out, so the selection reads as
                        // travelling to where you tapped.
                        .matchedGeometryEffect(id: "tab", in: indicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.identifier(for: item.title))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
