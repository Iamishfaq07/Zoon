import SwiftUI

/// A `VStack` whose children arrive in sequence instead of all at once.
///
/// The four tabs cascade their cards with `.entrance(index)` written out per
/// child. Nearly forty pushed screens did not, because doing it by hand
/// means numbering every child and renumbering them whenever one moves —
/// which is why those screens simply never got it.
///
/// `Group(subviews:)` enumerates the children at build time, so the index
/// comes from the position in the stack rather than from a number someone
/// has to maintain. Swapping `VStack` for `CascadeStack` is the whole change
/// at a call site, and a child inserted in the middle renumbers everything
/// after it for free.
///
/// Reduce Motion is handled where it already was: `.entrance` shows its
/// content immediately when the setting is on, so this cascades or it does
/// not, and no call site has to know.
struct CascadeStack<Content: View>: View {

    /// `.center`, matching `VStack`'s own default — this is a drop-in
    /// replacement, and a different default would silently re-align every
    /// screen converted from a `VStack(spacing:)` that named no alignment.
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index].entrance(index)
                }
            }
        }
    }
}
