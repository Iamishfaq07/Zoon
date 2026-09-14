import SwiftUI

/// Keeps a time-of-day band current while a screen stays open.
///
/// **The bug.** `Band.current()` is read once — on appear for the ambient
/// background, and on each body evaluation for Today, which amounts to the
/// same thing since nothing invalidated the body. Leave Today open at 16:59
/// and at 17:01 it is still drawing the day hero on the day gradient: the
/// app knows the band changed and has no reason to look.
///
/// **Why not a timer.** Polling every second to notice four transitions a
/// day is battery spent to learn nothing 86,396 times. This sleeps until the
/// *next boundary*, updates, and sleeps again — four wakeups a day at most,
/// and none while the screen is closed, because `.task` is cancelled when
/// the view goes away.
///
/// **The other four triggers**, each a real way the band can change without a
/// boundary being crossed while the app was awake:
///
/// - returning to the foreground, having been suspended across one
/// - the clock being set
/// - the timezone changing, which moves every boundary at once
/// - the calendar day rolling over
///
/// Foundation notifications and `scenePhase` rather than UIKit, because this
/// file compiles into the watch and widget targets too.
struct PhaseBoundaryRefresh: ViewModifier {

    @Binding var band: ZoonAmbientBackground.Band
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await followBoundaries() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
            ) { _ in refresh() }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            ) { _ in refresh() }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            ) { _ in refresh() }
    }

    private func refresh() {
        let current = ZoonAmbientBackground.Band.current()
        guard current != band else { return }
        band = current
    }

    /// Sleeps to each boundary in turn. Re-reads the *next* boundary after
    /// every wake rather than assuming a fixed interval, so a timezone change
    /// mid-sleep is corrected on the following pass instead of drifting.
    private func followBoundaries() async {
        while !Task.isCancelled {
            guard let next = ZoonAmbientBackground.Band.nextBoundary() else { return }
            let seconds = next.timeIntervalSinceNow
            // A boundary already behind us means the clock moved while we
            // slept; refresh immediately rather than waiting a whole day.
            guard seconds > 0 else {
                refresh()
                return
            }
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return  // cancelled: the screen went away
            }
            refresh()
        }
    }
}

extension View {
    /// Re-reads `band` when the time-of-day band actually changes.
    func refreshingOnPhaseBoundary(
        _ band: Binding<ZoonAmbientBackground.Band>
    ) -> some View {
        modifier(PhaseBoundaryRefresh(band: band))
    }
}
