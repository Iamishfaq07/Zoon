import SwiftUI

/// The first frame of a cold launch.
///
/// iOS shows a generated launch screen — a flat sheet of the app's background
/// colour — while the process starts, and then cuts straight to whatever the
/// first tab happens to be mid-load. That cut is the least considered moment
/// in the app: the one screen everybody sees every single time, and the only
/// one nobody designed.
///
/// This replaces the cut with a hand-off. The same moon the rest of the app
/// draws rises out of the dark, the wordmark settles under it, and the whole
/// thing fades away over the app already laid out behind it, so Today is
/// never seen assembling itself.
///
/// It plays once per process launch and never blocks anything: the app behind
/// it has already started loading, so the hold below is spent on work that
/// was happening anyway rather than on a wait invented for the animation.
struct ZoonSplash: View {

    /// Called when the splash has finished and the app should take over.
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the whole sequence. One flag rather than four: every element
    /// animates the same property with its own delay, which keeps the timing
    /// readable as a sequence instead of scattered across handlers.
    @State private var risen = false
    @State private var starsIn = false

    var body: some View {
        ZStack {
            ZoonNightGround()
                .ignoresSafeArea()

            NightSky(starCount: 46)
                .opacity(starsIn ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 26) {
                moon
                wordmark
            }
        }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zoon")
    }

    // MARK: - Pieces

    private var moon: some View {
        ZStack {
            // No halo ring here.
            //
            // This drew a separate radial gradient from radius 62 to 116 in
            // the moon's own lit purple, around a 132pt moon whose own
            // radius is 66 -- so it began exactly at the limb and read as a
            // purple ring fitted around the moon rather than as light coming
            // off it. `MoonFill` already carries its own glow; a second one
            // starting where the disc ends can only ever draw an outline.
            MoonFill(fill: 0.78, active: true, size: 132)
                .scaleEffect(risen ? 1 : 0.82)
                .opacity(risen ? 1 : 0)
                // Rising, literally: 22pt of travel, which is enough to read
                // as movement at this size and small enough not to look like
                // the moon was dropped in from off-screen.
                .offset(y: risen ? 0 : 22)
        }
    }

    private var wordmark: some View {
        VStack(spacing: 7) {
            Text("Zoon")
                .font(Theme.numeral(36))
                .tracking(3)
                .foregroundStyle(Theme.Family.Moon.lit)

            Text("Sleep, understood")
                .font(Theme.label(13, weight: .medium))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSecondary)
        }
        .opacity(risen ? 1 : 0)
        .offset(y: risen ? 0 : 10)
    }

    // MARK: - Sequence

    private func run() async {
        guard !reduceMotion else {
            // Still branded, still a first frame — just no movement. Held
            // briefly so it registers as a screen rather than a flash.
            risen = true
            starsIn = true
            try? await Task.sleep(for: .seconds(0.45))
            if !LaunchOptions.holdsSplash { onFinish() }
            return
        }

        withAnimation(Motion.splash.delay(Motion.Entry.hero)) { risen = true }
        withAnimation(.easeOut(duration: 1.1).delay(Motion.Entry.background)) { starsIn = true }

        try? await Task.sleep(for: .seconds(Motion.splashHold))
        // `-zoonSplash YES` holds the splash up so the screenshot workflow
        // can photograph it; it would otherwise be long gone by the time
        // capture fires.
        guard !LaunchOptions.holdsSplash else { return }
        onFinish()
    }
}

#Preview("Splash") {
    ZoonSplash(onFinish: {})
        .preferredColorScheme(.dark)
}
