import SwiftUI

/// Home for metrics Zoon computes but does not stand behind as clinically
/// meaningful.
///
/// Cardiovascular Age is the founding member: it's a plausible-looking single
/// number derived from an internally-invented HRV/resting-HR formula, not a
/// validated clinical measure, and a number like "your cardiovascular age is
/// 47" reads as a medical finding no matter how it's badged. On the Today
/// screen -- beside Recovery and Body Signals, which are computed against the
/// user's own measured baselines -- it borrowed a credibility it hasn't
/// earned. Here it sits behind a deliberate tap, under a heading that says
/// plainly what it is.
///
/// Anything added here must stay out of the scores that drive the app:
/// nothing in Labs feeds Sleep Intelligence, Recovery, or Sleep Need.
struct LabsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var context: DayContext? { coordinator.state.context }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                preamble

                if let cvAge = context?.cardiovascularAge {
                    CardiovascularAgeCard(cvAge: cvAge)
                } else {
                    ContentUnavailableView(
                        "Not enough history yet",
                        systemImage: "flask",
                        description: Text("Experimental metrics need a few weeks of nights before they can be estimated.")
                    )
                    .padding(.top, 30)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Labs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preamble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("What this is", systemImage: "flask")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                Experimental estimates built from Zoon's own formulas rather than \
                validated clinical measures. They're here because they're interesting \
                to watch over time, not because they're diagnostic -- treat them as \
                curiosities, not findings. Nothing on this screen affects your Sleep \
                Intelligence, Recovery, or Sleep Need.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Labs") {
    NavigationStack { LabsView() }
        .zoonPreviewEnvironment()
}
