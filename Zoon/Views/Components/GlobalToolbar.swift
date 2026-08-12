import SwiftUI

/// The two actions reachable from every tab: logging something in the
/// Journal, and everything that used to live on the More tab.
///
/// Applied to each of the four tab roots individually rather than once on a
/// wrapping `NavigationStack`, because each tab already owns its own
/// `NavigationStack` and title -- the navigation redesign moved Journal and
/// Settings off the tab bar, it didn't collapse four independent stacks into
/// one.
private struct GlobalToolbar: ViewModifier {

    @Environment(GlobalPresentation.self) private var presentation

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    presentation.presentJournal()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Log")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    presentation.presentMore()
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }
}

extension View {
    func zoonGlobalToolbar() -> some View {
        modifier(GlobalToolbar())
    }
}
