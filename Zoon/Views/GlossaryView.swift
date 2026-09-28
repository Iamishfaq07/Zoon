import SwiftUI

/// Every word the app puts on a screen, in plain language.
///
/// `SleepVocabulary` held the terms, but only an info button beside some
/// metrics ever showed one, so someone meeting "Deep", "Recovery signal" or
/// "Daily load" elsewhere had nowhere to look them up. This is that place:
/// searchable, one tap to open a term, what is usual underneath.
struct GlossaryView: View {

    @State private var query = ""
    @State private var expanded: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var terms: [SleepVocabulary.Term] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SleepVocabulary.all }
        return SleepVocabulary.all.filter { term in
            [term.plain, term.technical ?? "", term.meaning]
                .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Every word Zoon uses, said plainly. Tap one to read more.")
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                if terms.isEmpty {
                    Text("No word matches “\(query)”.")
                        .font(Theme.text(15))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 20)
                }

                ForEach(terms, id: \.plain) { term in
                    row(term)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .searchable(text: $query, prompt: "Search words")
        .nightBackground()
        .navigationTitle("What the words mean")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ term: SleepVocabulary.Term) -> some View {
        let isOpen = expanded.contains(term.plain)
        return Button {
            withAnimation(Motion.respecting(reduceMotion, Motion.tap)) {
                if isOpen { expanded.remove(term.plain) } else { expanded.insert(term.plain) }
            }
            Haptics.select()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: term.symbol)
                        .font(Theme.text(16, weight: .semibold))
                        .foregroundStyle(Theme.Metric.sleep)
                        .frame(width: 36, height: 36)
                        .background(Theme.Metric.sleep.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .symbolEffect(.bounce, value: isOpen)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(term.plain)
                            .font(Theme.label(16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        if let technical = term.technical {
                            Text("Also called \(technical)")
                                .font(Theme.text(13))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(Theme.text(13, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                if isOpen {
                    Text(term.meaning)
                        .font(Theme.text(15))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if let typical = term.typical {
                        Label {
                            Text(typical)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "ruler")
                        }
                        .font(Theme.text(14))
                        .foregroundStyle(Theme.inkSecondary)
                        .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isOpen ? "Hides the explanation" : "Shows what it means")
    }
}

#Preview("Glossary") {
    NavigationStack { GlossaryView() }
        .preferredColorScheme(.dark)
}
