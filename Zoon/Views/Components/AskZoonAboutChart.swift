import SwiftUI

/// "Ask Zoon about this" for a selected point on a chart.
///
/// Sits *below* the chart rather than inside the plot. A button placed in a
/// Chart annotation competes with `chartXSelection`'s own drag recogniser
/// for the same touches, and the affordance that matters most here is the
/// one that reliably works.
///
/// The exact question is printed under the button before anything is sent.
/// Nothing is asked on the user's behalf that they cannot read first, and a
/// surprising answer can always be traced to the question that produced it.
struct AskZoonAboutChart: View {
    let question: ChartQuestion
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(Theme.text(11, weight: .semibold))
                    Text("Ask Zoon about this")
                        .font(Theme.text(13, weight: .semibold))
                }
                .foregroundStyle(Theme.Family.sleep)
                Text(question.question)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Zoon about this")
        .accessibilityHint(question.question)
    }
}

extension View {

    /// Presents the coach seeded with `question`, for a screen that offers
    /// `AskZoonAboutChart`.
    ///
    /// `night` is the night the conversation is otherwise grounded in --
    /// the coach always needs one, and a chart question narrows that ground
    /// rather than replacing it.
    func askZoonSheet(about question: Binding<ChartQuestion?>, night: SleepNightFeatures?) -> some View {
        sheet(item: question) { asked in
            NavigationStack {
                if let night {
                    CoachChatView(night: night, chartQuestion: asked)
                } else {
                    ContentUnavailableView(
                        "No night to ask about yet",
                        systemImage: "moon.zzz",
                        description: Text("Zoon needs at least one recorded night before it can answer questions about a chart.")
                    )
                    .nightBackground()
                }
            }
        }
    }
}

#Preview("Ask Zoon about this") {
    AskZoonAboutChart(
        question: ChartQuestion(
            subject: .trend(.hrv),
            selected: .init(date: .now, value: 42),
            baseline: 58,
            baselineNightCount: 21
        ),
        action: {}
    )
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}
