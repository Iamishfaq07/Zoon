import SwiftUI

/// Cross-tab presentation state: the Journal and the More/Settings screen are
/// reachable from every tab, not owned by any one of them, so their
/// presentation flags live above the tabs rather than inside one.
///
/// Exists because the navigation redesign (Today/Sleep/Insights/Coach) frees
/// up two tab slots by moving Journal and Settings off the tab bar — Journal
/// becomes a "Log" toolbar button reachable everywhere, Settings folds under
/// a profile button — and both need somewhere to keep their open/closed and
/// pushed-path state that outlives whichever tab happened to trigger them.
@Observable
final class GlobalPresentation {
    var showingJournal = false
    var showingMore = false
    /// Owned here rather than by `MoreView` so a Control Center or Shortcuts
    /// deep link (Report, Settings, Badges) can push directly onto it the
    /// moment the sheet opens, the same way it used to push onto the old
    /// More tab's own path.
    var morePath = NavigationPath()

    func presentJournal() {
        showingJournal = true
    }

    /// - Parameter destination: pushed onto the More sheet's path once it's
    ///   open, for deep links that target a screen living inside it.
    func presentMore(pushing destination: DeepLink.Destination? = nil) {
        if let destination {
            morePath = NavigationPath()
            morePath.append(destination)
        }
        showingMore = true
    }
}
